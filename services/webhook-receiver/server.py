#!/usr/bin/env python3
"""
Webhook Receiver Service

Receives webhooks from external sources (GitHub, IFTTT, etc.) and converts them
to sense events for Samara to process.

Features:
- Per-source authentication (shared secrets)
- Rate limiting
- IP allowlisting (optional)
- Automatic sense event generation

Usage:
    python server.py                    # Run on default port 8082
    python server.py --port 8083        # Run on custom port
    python server.py --config path.json # Use custom config
"""

import asyncio
import hashlib
import hmac
import json
import os
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Request, HTTPException, Header
from fastapi.responses import JSONResponse
import uvicorn

def resolve_mind_dir() -> Path:
    override = os.environ.get("SAMARA_MIND_PATH") or os.environ.get("MIND_PATH")
    if override:
        return Path(os.path.expanduser(override))
    return Path.home() / ".claude-mind"


# Configuration paths
MIND_DIR = resolve_mind_dir()
CREDENTIALS_DIR = MIND_DIR / "self" / "credentials"
SENSES_DIR = MIND_DIR / "system" / "senses"
STATE_DIR = MIND_DIR / "state"
WEBHOOK_CONFIG = CREDENTIALS_DIR / "webhook-secrets.json"

# Ensure directories exist
SENSES_DIR.mkdir(parents=True, exist_ok=True)
STATE_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Samara Webhook Receiver", version="1.0.0")

# Rate limiting state
rate_limits: dict[str, list[float]] = defaultdict(list)


def load_config() -> dict:
    """Load webhook configuration."""
    if not WEBHOOK_CONFIG.exists():
        # Create default config
        default_config = {
            "sources": {
                "github": {
                    "secret": os.environ.get("WEBHOOK_SECRET_GITHUB", "change-me"),
                    "allowed_ips": None,
                    "rate_limit": "30/minute"
                },
                "ifttt": {
                    "secret": os.environ.get("WEBHOOK_SECRET_IFTTT", "change-me"),
                    "allowed_ips": None,
                    "rate_limit": "10/minute"
                },
                "test": {
                    "secret": "test-secret",
                    "allowed_ips": ["127.0.0.1", "::1"],
                    "rate_limit": "60/minute"
                }
            }
        }
        CREDENTIALS_DIR.mkdir(parents=True, exist_ok=True)
        WEBHOOK_CONFIG.write_text(json.dumps(default_config, indent=2))
        return default_config

    return json.loads(WEBHOOK_CONFIG.read_text())


def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    """Verify webhook signature (GitHub-style HMAC-SHA256)."""
    if not signature:
        return False

    # Handle different signature formats
    if signature.startswith("sha256="):
        signature = signature[7:]

    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


def check_rate_limit(source_id: str, limit_str: str) -> bool:
    """Check if request is within rate limit."""
    # Parse limit string (e.g., "30/minute")
    parts = limit_str.split("/")
    if len(parts) != 2:
        return True

    count = int(parts[0])
    period = parts[1]

    period_seconds = {
        "second": 1,
        "minute": 60,
        "hour": 3600
    }.get(period, 60)

    now = time.time()
    cutoff = now - period_seconds

    # Clean old entries
    rate_limits[source_id] = [t for t in rate_limits[source_id] if t > cutoff]

    # Check limit
    if len(rate_limits[source_id]) >= count:
        return False

    rate_limits[source_id].append(now)
    return True


def check_ip_allowed(client_ip: str, allowed_ips: Optional[list]) -> bool:
    """Check if client IP is in allowlist."""
    if allowed_ips is None:
        return True
    return client_ip in allowed_ips


def create_sense_event(source_id: str, data: dict, headers: dict) -> str:
    """Create a sense event file and return the filename."""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    filename = f"webhook-{source_id}-{timestamp}.event.json"

    event = {
        "sense": "webhook",
        "timestamp": datetime.now().isoformat(),
        "priority": determine_priority(source_id, data),
        "data": {
            "source": source_id,
            "payload": data,
            "headers": {k: v for k, v in headers.items() if k.lower().startswith("x-")}
        },
        "context": {
            "suggested_prompt": generate_prompt_hint(source_id, data)
        }
    }

    event_path = SENSES_DIR / filename
    event_path.write_text(json.dumps(event, indent=2))

    return filename


def determine_priority(source_id: str, data: dict) -> str:
    """Determine event priority based on source and content."""
    # GitHub: PRs and issues are normal, security alerts are immediate
    if source_id == "github":
        event_type = data.get("action", "")
        if "security" in str(data).lower():
            return "immediate"
        if event_type in ["opened", "closed", "merged"]:
            return "normal"
        return "background"

    # Default
    return "normal"


def generate_prompt_hint(source_id: str, data: dict) -> str:
    """Generate a suggested prompt based on webhook content."""
    if source_id == "github":
        action = data.get("action", "event")
        repo = data.get("repository", {}).get("full_name", "unknown repo")
        return f"GitHub {action} in {repo}"

    if source_id == "ifttt":
        return f"IFTTT trigger: {data.get('triggerName', 'unknown')}"

    return f"Webhook from {source_id}"


# =============================================================================
# Browser History Webhook Handler (MUST be defined before generic webhook)
# =============================================================================

def create_browser_history_event(data: dict) -> str:
    """Create a sense event for browser history data."""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    filename = f"browser-history-{timestamp}.event.json"

    visits = data.get("visits", [])
    domains = data.get("domains_summary", {})
    device = data.get("device", "unknown")

    # Determine priority based on browsing patterns
    priority = "background"
    suggested_prompt = None

    if domains:
        # Check for concentrated research (5+ visits to same domain)
        max_visits = max(domains.values()) if domains else 0
        top_domains = sorted(domains.items(), key=lambda x: -x[1])[:3]

        if max_visits >= 5:
            priority = "normal"
            top_domain = top_domains[0][0] if top_domains else "unknown"
            suggested_prompt = (
                f"Browsing pattern detected: {max_visits} visits to {top_domain}. "
                f"Consider asking what they're researching."
            )

        # Format domain summary for context
        domain_summary = ", ".join(f"{d}({c})" for d, c in top_domains[:5])
    else:
        domain_summary = "no domains"

    event = {
        "sense": "browser_history",
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "priority": priority,
        "data": {
            "type": "browsing_update",
            "device": device,
            "visit_count": len(visits),
            "visits": visits[:50],  # Limit to 50 most recent
            "domains_summary": domains,
        },
        "context": {
            "suggested_prompt": suggested_prompt or f"Browser update: {len(visits)} visits. Top: {domain_summary}",
            "suppress_response": priority == "background",  # Don't message for background events
        }
    }

    event_path = SENSES_DIR / filename
    event_path.write_text(json.dumps(event, indent=2))

    # Also append to history file for longer-term analysis
    history_file = STATE_DIR / "browser-history.jsonl"
    with history_file.open("a") as f:
        for visit in visits:
            visit_record = {
                "timestamp": visit.get("timestamp"),
                "url": visit.get("url"),
                "title": visit.get("title"),
                "browser": visit.get("browser"),
                "device": device,
            }
            f.write(json.dumps(visit_record) + "\n")

    return filename


@app.post("/webhook/browser_history")
async def receive_browser_history(
    request: Request,
    x_hub_signature_256: Optional[str] = Header(None),
):
    """
    Receive browser history from client exporter.

    This is a dedicated endpoint for browser history that creates
    browser_history sense events instead of generic webhook events.
    """
    config = load_config()

    # Check if browser_history source is registered
    source_config = config.get("sources", {}).get("browser_history")
    if not source_config:
        # Allow with warning if not explicitly configured
        source_config = {"secret": "", "rate_limit": "60/minute"}

    # Check rate limit
    rate_limit = source_config.get("rate_limit", "60/minute")
    if not check_rate_limit("browser_history", rate_limit):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    # Get request body
    body = await request.body()

    # Verify authentication if secret is configured
    secret = source_config.get("secret", "")
    if secret and secret != "change-me":
        if x_hub_signature_256:
            if not verify_signature(body, x_hub_signature_256, secret):
                raise HTTPException(status_code=401, detail="Invalid signature")
        else:
            raise HTTPException(status_code=401, detail="Missing authentication")

    # Parse body
    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    # Validate expected fields
    if "visits" not in data:
        raise HTTPException(status_code=400, detail="Missing 'visits' field")

    # Create browser history sense event
    filename = create_browser_history_event(data)

    return JSONResponse({
        "status": "accepted",
        "event_file": filename,
        "visits_received": len(data.get("visits", [])),
        "source": "browser_history"
    })


# =============================================================================
# Generic Webhook Handler
# =============================================================================

@app.post("/webhook/{source_id}")
async def receive_webhook(
    source_id: str,
    request: Request,
    x_webhook_secret: Optional[str] = Header(None),
    x_hub_signature_256: Optional[str] = Header(None),
):
    """Receive a webhook from an external source."""
    config = load_config()

    # Check if source is registered
    if source_id not in config.get("sources", {}):
        raise HTTPException(status_code=404, detail=f"Unknown source: {source_id}")

    source_config = config["sources"][source_id]

    # Check IP allowlist
    client_ip = request.client.host
    if not check_ip_allowed(client_ip, source_config.get("allowed_ips")):
        raise HTTPException(status_code=403, detail="IP not allowed")

    # Check rate limit
    rate_limit = source_config.get("rate_limit", "60/minute")
    if not check_rate_limit(source_id, rate_limit):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    # Get request body
    body = await request.body()

    # Verify authentication
    secret = source_config.get("secret", "")

    if secret and secret != "change-me":
        # If secret is set and not default, require authentication
        if x_hub_signature_256:
            # HMAC-SHA256 signature verification (GitHub-style)
            if not verify_signature(body, x_hub_signature_256, secret):
                raise HTTPException(status_code=401, detail="Invalid signature")
        elif x_webhook_secret:
            # Direct secret comparison (IFTTT-style)
            if x_webhook_secret != secret:
                raise HTTPException(status_code=401, detail="Invalid secret")
        else:
            raise HTTPException(status_code=401, detail="Missing authentication")

    # Parse body
    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        # Try form data
        data = dict(await request.form()) if body else {}

    # Create sense event
    headers = dict(request.headers)
    filename = create_sense_event(source_id, data, headers)

    return JSONResponse({
        "status": "accepted",
        "event_file": filename,
        "source": source_id
    })


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/status")
async def status():
    """Get receiver status."""
    config = load_config()
    return {
        "registered_sources": list(config.get("sources", {}).keys()),
        "senses_dir": str(SENSES_DIR),
        "recent_events": len(list(SENSES_DIR.glob("*.event.json")))
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Webhook Receiver Service")
    parser.add_argument("--port", type=int, default=8082, help="Port to listen on")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--config", help="Path to config file")
    args = parser.parse_args()

    if args.config:
        global WEBHOOK_CONFIG
        WEBHOOK_CONFIG = Path(args.config)

    print(f"Starting webhook receiver on {args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
