#!/usr/bin/env python3
"""
Browser History Exporter

Reads browser history from Chrome/Dia and Safari on macOS, then POSTs
to Claude's webhook-receiver for sense processing.

Features:
- Incremental exports (tracks last-seen timestamp)
- Deduplicates URLs visited in multiple browsers
- Works with locked databases (copies before reading)
- Domain summarization for pattern detection

Usage:
    ./exporter.py                 # Run once
    ./exporter.py --daemon        # Run continuously (for testing)
"""

import argparse
import hashlib
import hmac
import json
import os
import shutil
import sqlite3
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import requests

# Configuration
CONFIG_PATH = Path.home() / ".claude-client" / "config.json"
STATE_PATH = Path.home() / ".claude-client" / "browser-history-state.json"

# Browser history database locations
BROWSER_PATHS = {
    "dia": Path.home() / "Library/Application Support/Dia/Default/History",
    "chrome": Path.home() / "Library/Application Support/Google/Chrome/Default/History",
    "safari": Path.home() / "Library/Safari/History.db",
    "arc": Path.home() / "Library/Application Support/Arc/User Data/Default/History",
}

# Timestamp conversion constants
WEBKIT_EPOCH_OFFSET = 11644473600  # Seconds between 1601-01-01 and 1970-01-01
COREDATA_EPOCH_OFFSET = 978307200  # Seconds between 2001-01-01 and 1970-01-01


def load_config() -> dict:
    """Load configuration from ~/.claude-client/config.json"""
    if not CONFIG_PATH.exists():
        # Create default config
        default = {
            "webhook_url": "https://your-webhook-url.com/webhook/browser_history",
            "webhook_secret": "change-me",
            "browsers": ["dia", "safari"],
            "poll_interval_min": 15,
            "device_name": os.uname().nodename,
        }
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(default, indent=2))
        print(f"Created default config at {CONFIG_PATH}")
        print("Please edit it with your webhook URL and secret.")
        return default

    return json.loads(CONFIG_PATH.read_text())


def load_state() -> dict:
    """Load state (last-seen timestamps) from disk."""
    if not STATE_PATH.exists():
        return {"last_timestamps": {}}
    return json.loads(STATE_PATH.read_text())


def save_state(state: dict):
    """Save state to disk."""
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2))


def webkit_to_unix(webkit_timestamp: int) -> float:
    """Convert WebKit timestamp (microseconds since 1601) to Unix timestamp."""
    return (webkit_timestamp / 1_000_000) - WEBKIT_EPOCH_OFFSET


def coredata_to_unix(coredata_timestamp: float) -> float:
    """Convert Core Data timestamp (seconds since 2001) to Unix timestamp."""
    return coredata_timestamp + COREDATA_EPOCH_OFFSET


def copy_locked_db(db_path: Path) -> Optional[Path]:
    """
    Copy a potentially locked database to a temp location.
    Returns the temp path, or None if the original doesn't exist.
    """
    if not db_path.exists():
        return None

    temp_dir = Path(tempfile.mkdtemp())
    temp_db = temp_dir / "history_copy.db"

    try:
        shutil.copy2(db_path, temp_db)
        # Also copy WAL and SHM files if they exist (for Chrome/Dia)
        for ext in ["-wal", "-shm"]:
            wal_path = Path(str(db_path) + ext)
            if wal_path.exists():
                shutil.copy2(wal_path, Path(str(temp_db) + ext))
        return temp_db
    except Exception as e:
        print(f"Error copying database {db_path}: {e}")
        return None


def read_chrome_history(db_path: Path, since_timestamp: float) -> list[dict]:
    """
    Read history from Chrome/Dia/Arc SQLite database.
    Returns list of visit dicts.
    """
    temp_db = copy_locked_db(db_path)
    if not temp_db:
        return []

    visits = []
    try:
        conn = sqlite3.connect(f"file:{temp_db}?mode=ro", uri=True)
        cursor = conn.cursor()

        # Convert Unix timestamp to WebKit timestamp for query
        webkit_since = int((since_timestamp + WEBKIT_EPOCH_OFFSET) * 1_000_000)

        cursor.execute(
            """
            SELECT u.url, u.title, v.visit_time
            FROM visits v
            JOIN urls u ON v.url = u.id
            WHERE v.visit_time > ?
            ORDER BY v.visit_time ASC
            LIMIT 1000
        """,
            (webkit_since,),
        )

        for url, title, visit_time in cursor.fetchall():
            unix_time = webkit_to_unix(visit_time)
            visits.append(
                {
                    "url": url,
                    "title": title or "",
                    "timestamp": datetime.fromtimestamp(
                        unix_time, tz=timezone.utc
                    ).isoformat(),
                    "unix_timestamp": unix_time,
                }
            )

        conn.close()
    except Exception as e:
        print(f"Error reading Chrome/Dia history: {e}")
    finally:
        # Clean up temp files
        if temp_db and temp_db.parent.exists():
            shutil.rmtree(temp_db.parent, ignore_errors=True)

    return visits


def read_safari_history(db_path: Path, since_timestamp: float) -> list[dict]:
    """
    Read history from Safari SQLite database.
    Returns list of visit dicts.
    """
    temp_db = copy_locked_db(db_path)
    if not temp_db:
        return []

    visits = []
    try:
        conn = sqlite3.connect(f"file:{temp_db}?mode=ro", uri=True)
        cursor = conn.cursor()

        # Convert Unix timestamp to Core Data timestamp for query
        coredata_since = since_timestamp - COREDATA_EPOCH_OFFSET

        cursor.execute(
            """
            SELECT hi.url, hv.title, hv.visit_time
            FROM history_visits hv
            JOIN history_items hi ON hv.history_item = hi.id
            WHERE hv.visit_time > ?
            ORDER BY hv.visit_time ASC
            LIMIT 1000
        """,
            (coredata_since,),
        )

        for url, title, visit_time in cursor.fetchall():
            unix_time = coredata_to_unix(visit_time)
            visits.append(
                {
                    "url": url,
                    "title": title or "",
                    "timestamp": datetime.fromtimestamp(
                        unix_time, tz=timezone.utc
                    ).isoformat(),
                    "unix_timestamp": unix_time,
                }
            )

        conn.close()
    except Exception as e:
        print(f"Error reading Safari history: {e}")
    finally:
        # Clean up temp files
        if temp_db and temp_db.parent.exists():
            shutil.rmtree(temp_db.parent, ignore_errors=True)

    return visits


def read_browser_history(browser: str, since_timestamp: float) -> list[dict]:
    """Read history from a specific browser."""
    db_path = BROWSER_PATHS.get(browser)
    if not db_path:
        print(f"Unknown browser: {browser}")
        return []

    if browser == "safari":
        visits = read_safari_history(db_path, since_timestamp)
    else:
        # Chrome, Dia, Arc all use the same format
        visits = read_chrome_history(db_path, since_timestamp)

    # Tag with browser name
    for v in visits:
        v["browser"] = browser

    return visits


def deduplicate_visits(visits: list[dict]) -> list[dict]:
    """
    Deduplicate visits by URL within a short time window.
    If the same URL appears in multiple browsers within 60 seconds,
    keep only the first one.
    """
    seen = {}  # url -> earliest_timestamp
    deduped = []

    for v in sorted(visits, key=lambda x: x["unix_timestamp"]):
        url = v["url"]
        ts = v["unix_timestamp"]

        if url in seen:
            # If within 60 seconds of a previous visit, skip
            if ts - seen[url] < 60:
                continue

        seen[url] = ts
        deduped.append(v)

    return deduped


def summarize_domains(visits: list[dict]) -> dict[str, int]:
    """Count visits per domain."""
    counts = defaultdict(int)
    for v in visits:
        try:
            domain = urlparse(v["url"]).netloc
            if domain:
                counts[domain] += 1
        except Exception:
            pass

    # Sort by count descending, limit to top 20
    return dict(sorted(counts.items(), key=lambda x: -x[1])[:20])


def sign_payload(payload: str, secret: str) -> str:
    """Generate HMAC-SHA256 signature for payload."""
    return "sha256=" + hmac.new(
        secret.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()


def send_to_webhook(config: dict, visits: list[dict], domains: dict[str, int]) -> bool:
    """POST browser history to webhook receiver."""
    url = config.get("webhook_url", "")
    secret = config.get("webhook_secret", "")
    device = config.get("device_name", "unknown")

    if not url or url == "https://your-webhook-url.com/webhook/browser_history":
        print("Webhook URL not configured. Edit ~/.claude-client/config.json")
        return False

    payload = {
        "source": "browser_history",
        "device": device,
        "browsers": config.get("browsers", []),
        "visits": visits,
        "domains_summary": domains,
        "export_timestamp": datetime.now(tz=timezone.utc).isoformat(),
    }

    payload_json = json.dumps(payload)
    headers = {
        "Content-Type": "application/json",
        "X-Hub-Signature-256": sign_payload(payload_json, secret),
    }

    try:
        resp = requests.post(url, data=payload_json, headers=headers, timeout=30)
        if resp.status_code == 200:
            result = resp.json()
            print(f"Sent {len(visits)} visits. Response: {result.get('status', 'ok')}")
            return True
        else:
            print(f"Webhook returned {resp.status_code}: {resp.text}")
            return False
    except requests.RequestException as e:
        print(f"Failed to send to webhook: {e}")
        return False


def export_history(config: dict, state: dict) -> dict:
    """
    Main export function.
    Reads history from all configured browsers, deduplicates, and sends to webhook.
    Returns updated state.
    """
    browsers = config.get("browsers", ["dia", "safari"])
    last_timestamps = state.get("last_timestamps", {})

    all_visits = []
    new_last_timestamps = {}

    for browser in browsers:
        since = last_timestamps.get(browser, 0)
        print(f"Reading {browser} history since {datetime.fromtimestamp(since) if since else 'beginning'}...")

        visits = read_browser_history(browser, since)
        print(f"  Found {len(visits)} new visits")

        if visits:
            # Track the latest timestamp for this browser
            latest = max(v["unix_timestamp"] for v in visits)
            new_last_timestamps[browser] = latest
        else:
            new_last_timestamps[browser] = since

        all_visits.extend(visits)

    # Deduplicate across browsers
    deduped = deduplicate_visits(all_visits)
    print(f"Total visits after deduplication: {len(deduped)}")

    if deduped:
        # Summarize domains
        domains = summarize_domains(deduped)
        print(f"Top domains: {list(domains.keys())[:5]}")

        # Clean up visits for sending (remove internal unix_timestamp)
        for v in deduped:
            del v["unix_timestamp"]

        # Send to webhook
        if send_to_webhook(config, deduped, domains):
            # Only update timestamps on success
            state["last_timestamps"] = new_last_timestamps
    else:
        print("No new visits to export")
        state["last_timestamps"] = new_last_timestamps

    return state


def main():
    parser = argparse.ArgumentParser(description="Export browser history to Claude")
    parser.add_argument("--daemon", action="store_true", help="Run continuously")
    parser.add_argument("--interval", type=int, help="Poll interval in minutes")
    args = parser.parse_args()

    config = load_config()
    state = load_state()

    if args.daemon:
        interval = args.interval or config.get("poll_interval_min", 15)
        print(f"Running in daemon mode, polling every {interval} minutes")
        while True:
            state = export_history(config, state)
            save_state(state)
            time.sleep(interval * 60)
    else:
        state = export_history(config, state)
        save_state(state)


if __name__ == "__main__":
    main()
