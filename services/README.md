# Services

Python services that extend the organism's capabilities through background polling and HTTP endpoints.

---

## Service Overview

| Service | Type | Port | Schedule | Purpose |
|---------|------|------|----------|---------|
| `location-receiver` | HTTP | 8081 | Always | Receives GPS from Overland app |
| `webhook-receiver` | HTTP | 8082 | Always | Receives GitHub/IFTTT/browser webhooks |
| `mcp-memory-bridge` | HTTP | 8765 | Always | Shared memory for Claude Desktop/Web |
| `bluesky-watcher` | Poller | - | 15 min | Polls Bluesky notifications |
| `github-watcher` | Poller | - | 15 min | Polls GitHub notifications |
| `x-watcher` | Poller | - | 15 min | Polls X/Twitter mentions |
| `wallet-watcher` | Poller | - | 15 min | Monitors crypto wallet balances |
| `meeting-check` | Poller | - | 15 min | Detects meetings for prep/debrief |
| `wake-scheduler` | CLI | - | 15 min | Calculates adaptive wake times |
| `proactive` | Integrated | - | 15 min | Evaluates triggers for proactive messaging |

**Client-Side Services** (run on collaborator's devices):

| Service | Location | Schedule | Purpose |
|---------|----------|----------|---------|
| `browser-history-exporter` | É's Mac | 15 min | Exports browser history to Claude |

---

## HTTP Services (Always Running)

These run as persistent daemons via launchd.

### location-receiver (Port 8081)

Receives GPS data from [Overland](https://overland.p3k.app/) iOS app.

- Stores latest location in `~/.claude-mind/state/location.json`
- Appends history to `~/.claude-mind/state/location-history.jsonl`

### webhook-receiver (Port 8082)

Accepts webhooks from external services (GitHub, IFTTT, custom).

- Converts webhooks to sense events
- Supports HMAC-SHA256 signature verification
- Config: `~/.claude-mind/self/credentials/webhook-secrets.json`

### mcp-memory-bridge (Port 8765)

MCP server that allows Claude Desktop/Web to share memory with Claude Code.

- Exposes tools: `log_exchange`, `add_learning`, `search_memory`, etc.
- Can be exposed via Cloudflare Tunnel for remote access

---

## Client-Side Services

These run on the collaborator's devices and push data to Claude's Mac.

### browser-history-exporter (Client-Side)

Runs on É's Mac, exports browser history to Claude via webhook.

- Reads from Chrome/Dia, Safari, Arc databases
- Tracks incremental changes (doesn't re-send old history)
- Deduplicates across browsers
- POSTs to `webhook-receiver` at `/webhook/browser_history`

**Installation on É's Mac:**
```bash
cd clients/browser-history-exporter
./install.sh
# Edit ~/.claude-client/config.json with webhook URL and secret
```

**Server-side setup (Claude's Mac):**
```bash
# Add to ~/.claude-mind/self/credentials/webhook-secrets.json:
{
  "sources": {
    "browser_history": {
      "secret": "your-shared-secret",
      "rate_limit": "60/minute"
    }
  }
}
```

See `clients/browser-history-exporter/README.md` for details.

---

## Polling Services (launchd Interval)

These run every 15 minutes via launchd, check for new activity, and write sense events.

### Social Watchers

| Service | Checks For | Credentials |
|---------|------------|-------------|
| `bluesky-watcher` | Notifications, DMs | `~/.claude-mind/self/credentials/bluesky.json` |
| `github-watcher` | Notifications, mentions | `gh` CLI auth |
| `x-watcher` | Mentions, replies | `bird` CLI (browser cookies) |

### Other Pollers

| Service | Purpose |
|---------|---------|
| `wallet-watcher` | Monitors SOL/ETH/BTC balances for changes |
| `meeting-check` | Detects meetings starting soon or just ended |
| `wake-scheduler` | Decides whether to trigger wake cycles |

### Proactive Messaging

Runs as part of `wake-adaptive` (not a separate launchd job). Evaluates multiple trigger sources to decide when Claude should reach out:

- **Pattern triggers** — Conversation rhythm anomalies
- **Calendar triggers** — Upcoming/ended meetings
- **Browser triggers** — Research dives, search patterns
- **Location triggers** — Arrival/departure events
- **Anomaly triggers** — Unusual silence

When confidence exceeds 0.8 and safeguards pass (quiet hours, cooldown, etc.), generates a contextual message via Claude and sends via iMessage.

Toggle: `service-toggle proactive on/off`

See [Proactive Messaging](../docs/proactive-messaging.md) for full documentation.

---

## Sense Events

Polling services write sense events to `~/.claude-mind/system/senses/` as JSON files:

```json
{
  "sense": "bluesky",
  "timestamp": "2026-01-24T12:00:00Z",
  "priority": "normal",
  "data": { ... }
}
```

The `SenseDirectoryWatcher` in Samara.app picks these up and routes them through `SenseRouter.swift`.

---

## Managing Services

### Check Status

```bash
# List all Claude services
launchctl list | grep com.claude

# Check specific service
launchctl list | grep bluesky-watcher
```

### Start/Stop Services

```bash
# Load (start)
launchctl load ~/Library/LaunchAgents/com.claude.bluesky-watcher.plist

# Unload (stop)
launchctl unload ~/Library/LaunchAgents/com.claude.bluesky-watcher.plist
```

### Toggle via Script

```bash
# Show all service statuses
service-toggle list

# Enable/disable
service-toggle bluesky on
service-toggle bluesky off
```

---

## Logs

All services log to `~/.claude-mind/system/logs/`:

```bash
# View recent logs
tail -f ~/.claude-mind/system/logs/bluesky-watcher.log
tail -f ~/.claude-mind/system/logs/github-watcher.log
tail -f ~/.claude-mind/system/logs/x-watcher.log
```

---

## Adding a New Service

1. Create directory: `services/my-service/`
2. Add `server.py` with the service logic
3. Add `README.md` documenting the service
4. Create launchd plist template: `com.claude.my-service.plist.template`
5. If it's toggleable, add to `service-toggle` script
6. Document in this README

---

## Directory Structure

```
services/
├── README.md                 # This file
├── bluesky-watcher/
│   ├── server.py
│   ├── requirements.txt
│   └── README.md
├── github-watcher/
│   ├── server.py
│   └── README.md
├── location-receiver/
│   ├── server.py
│   ├── *.plist.template
│   └── README.md
├── mcp-memory-bridge/
│   ├── server.py
│   ├── pyproject.toml
│   ├── *.plist.template
│   └── README.md
├── meeting-check/
│   ├── *.plist.template
│   └── README.md
├── wake-scheduler/
│   ├── scheduler.py
│   ├── *.plist.template
│   └── README.md
├── wallet-watcher/
│   ├── server.py
│   ├── requirements.txt
│   ├── *.plist.template
│   └── README.md
├── webhook-receiver/
│   ├── server.py
│   ├── requirements.txt
│   ├── *.plist.template
│   └── README.md
└── x-watcher/
    ├── server.py
    ├── *.plist.template
    └── README.md

clients/                      # Services that run on collaborator's devices
└── browser-history-exporter/
    ├── exporter.py           # Main script
    ├── install.sh            # Installer
    ├── *.plist               # launchd template
    └── README.md
```
