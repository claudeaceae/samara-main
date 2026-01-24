#!/usr/bin/env python3
"""
X/Twitter Watcher - Satellite service that polls X for mentions
and writes sense events for Samara to process.

Designed to run via launchd every 15 minutes.

Uses bird CLI (https://github.com/steipete/bird) for X API access.
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any


def resolve_mind_dir() -> str:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return os.path.expanduser(override)
    home_dir = os.environ.get('HOME', os.path.expanduser('~'))
    return os.path.join(home_dir, '.claude-mind')


# Paths
MIND_DIR = resolve_mind_dir()
STATE_DIR = os.path.join(MIND_DIR, 'state')
SENSES_DIR = os.path.join(MIND_DIR, 'system', 'senses')
CREDS_FILE = os.path.join(MIND_DIR, 'self', 'credentials', 'x-cookies.json')
STATE_FILE = os.path.join(STATE_DIR, 'x-watcher-state.json')
LOG_FILE = os.path.join(MIND_DIR, 'system', 'logs', 'x-watcher.log')


def log(message: str):
    """Log to file and stdout."""
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    line = f"[{timestamp}] {message}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')


def load_config() -> Dict:
    """Load config.json to get entity handles."""
    config_path = os.path.join(MIND_DIR, 'config.json')
    try:
        with open(config_path) as f:
            return json.load(f)
    except Exception:
        return {}


def get_entity_x_handle() -> str:
    """Get entity's X handle from config (without @)."""
    config = load_config()
    handle = config.get('entity', {}).get('x', '')
    return handle.lstrip('@').lower()


def load_state() -> Dict:
    """Load persistent state."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except:
        return {"seen_ids": []}


def save_state(state: Dict):
    """Save persistent state."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def load_credentials() -> Optional[Dict]:
    """Load X credentials."""
    try:
        with open(CREDS_FILE) as f:
            return json.load(f)
    except Exception as e:
        log(f"Error loading credentials: {e}")
        return None


def write_sense_event(interactions: List[Dict], priority: str = "normal"):
    """Write a sense event for Samara to process."""
    os.makedirs(SENSES_DIR, exist_ok=True)

    event = {
        "sense": "x",
        "timestamp": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        "priority": priority,
        "data": {
            "type": "mentions",
            "count": len(interactions),
            "interactions": interactions
        },
        "context": {
            "suggested_prompt": build_prompt_hint(interactions)
        },
        "auth": {
            "source_id": "x-watcher"
        }
    }

    event_file = os.path.join(SENSES_DIR, 'x.event.json')
    with open(event_file, 'w') as f:
        json.dump(event, f, indent=2)

    log(f"Wrote sense event with {len(interactions)} interaction(s)")


def build_prompt_hint(interactions: List[Dict]) -> str:
    """Build a prompt hint for Claude based on the interactions."""
    types = {}
    for i in interactions:
        t = i.get('type', 'unknown')
        types[t] = types.get(t, 0) + 1

    parts = []
    for t, count in types.items():
        if count == 1:
            parts.append(f"1 {t.lower()}")
        else:
            parts.append(f"{count} {t.lower()}s")

    summary = ", ".join(parts)
    return f"You have new X/Twitter notifications: {summary}. Review and respond using bird CLI (bird reply <id> \"text\") or x-post for new tweets."


def fetch_mentions(creds: Dict, state: Dict) -> List[Dict]:
    """Fetch new mentions from X using bird CLI."""
    interactions = []

    # Set up environment for bird
    env = os.environ.copy()
    env['AUTH_TOKEN'] = creds.get('auth_token', '')
    env['CT0'] = creds.get('ct0', '')

    try:
        # Fetch mentions via bird CLI
        result = subprocess.run(
            ['bird', 'mentions', '--json'],
            capture_output=True,
            text=True,
            env=env,
            timeout=60
        )

        if result.returncode != 0:
            log(f"bird mentions failed: {result.stderr}")
            return interactions

        mentions = json.loads(result.stdout) if result.stdout.strip() else []

        seen_ids = set(state.get("seen_ids", []))

        for m in mentions:
            tweet_id = m.get("id", "")

            # Skip if we've seen this tweet
            if tweet_id in seen_ids:
                continue

            # Skip our own tweets
            author = m.get("author", {}).get("username", "")
            entity_handle = get_entity_x_handle()
            if entity_handle and author.lower() == entity_handle:
                continue

            interaction = {
                "type": "MENTION",
                "id": tweet_id,
                "author": author,
                "author_name": m.get("author", {}).get("name", ""),
                "text": m.get("text", ""),
                "created_at": m.get("createdAt", ""),
                "reply_count": m.get("replyCount", 0),
                "like_count": m.get("likeCount", 0),
                "conversation_id": m.get("conversationId", ""),
                "in_reply_to": m.get("inReplyToStatusId", "")
            }

            interactions.append(interaction)

            # Add to seen IDs
            if tweet_id:
                seen_ids.add(tweet_id)

        # Update state - keep last 500 IDs to avoid unbounded growth
        state["seen_ids"] = list(seen_ids)[-500:]

    except subprocess.TimeoutExpired:
        log("bird mentions timed out")
    except json.JSONDecodeError as e:
        log(f"Error parsing bird output: {e}")
    except Exception as e:
        log(f"Error fetching mentions: {e}")

    return interactions


def main():
    log("Starting X watcher...")

    # Check for bird CLI
    try:
        result = subprocess.run(['which', 'bird'], capture_output=True, text=True)
        if result.returncode != 0:
            log("Error: bird CLI not installed. Run: brew install steipete/tap/bird")
            sys.exit(1)
    except Exception as e:
        log(f"Error checking for bird CLI: {e}")
        sys.exit(1)

    # Load credentials
    creds = load_credentials()
    if not creds:
        log("No credentials found, exiting")
        sys.exit(1)

    if not creds.get('auth_token') or not creds.get('ct0'):
        log("Invalid credentials (missing auth_token or ct0), exiting")
        sys.exit(1)

    # Load state
    state = load_state()

    # Fetch interactions
    interactions = fetch_mentions(creds, state)

    # Save state
    save_state(state)

    # Write sense event if we have interactions
    if interactions:
        log(f"Found {len(interactions)} new interaction(s)")

        # All X mentions are treated as normal priority
        # (bird doesn't support DMs, so no immediate priority)
        priority = "normal"

        write_sense_event(interactions, priority)
    else:
        log("No new interactions")

    log("X watcher complete")


if __name__ == '__main__':
    main()
