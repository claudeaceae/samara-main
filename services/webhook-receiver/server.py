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
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Request, HTTPException, Header
from fastapi.responses import JSONResponse
import uvicorn

# Configuration paths
MIND_DIR = Path.home() / ".claude-mind"
CREDENTIALS_DIR = MIND_DIR / "credentials"
SENSES_DIR = MIND_DIR / "senses"
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
        "recent_events": len(list(SENSES_DIR.glob("webhook-*.event.json")))
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
