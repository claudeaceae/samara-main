# Services Reference

Python services that extend the organism's capabilities.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Service Overview

| Service | Port | Purpose |
|---------|------|---------|
| `location-receiver` | 8081 | Receives GPS updates from Overland app |
| `webhook-receiver` | 8082 | Receives webhooks from GitHub, IFTTT, custom sources |
| `wake-scheduler` | N/A | Calculates adaptive wake times (CLI, not server) |
| `mcp-memory-bridge` | 8765 | Shared memory layer for Claude Desktop/Web |
| `bluesky-watcher` | N/A | Polls Bluesky for notifications (launchd interval) |
| `github-watcher` | N/A | Polls GitHub for notifications (launchd interval) |
| `x-watcher` | N/A | Polls X/Twitter for mentions (launchd interval) |
| `wallet-watcher` | N/A | Monitors crypto wallet balances (launchd interval) |

---

## Webhook Receiver (Phase 4)

Accepts webhooks from external services and converts them to sense events.

```bash
# Start
~/.claude-mind/system/bin/webhook-receiver start

# Status
~/.claude-mind/system/bin/webhook-receiver status

# Stop
~/.claude-mind/system/bin/webhook-receiver stop
```

**Endpoints:**
- `POST /webhook/{source_id}` — Receive webhook (GitHub, IFTTT, custom)
- `GET /health` — Health check
- `GET /status` — Show registered sources

**Configuration:** `~/.claude-mind/credentials/webhook-secrets.json`

See `services/webhook-receiver/README.md` for detailed setup.

---

## MCP Memory Bridge

Allows Claude instances across different interfaces (Desktop, Web, Code) to share the same memory system.

**URL:** `https://your-domain.com/sse` (via Cloudflare Tunnel)

**Tools provided:**
- `log_exchange` — Log conversation turns
- `add_learning` — Record insights
- `search_memory` — Search across memory files
- `get_recent_context` — Get recent episodes/learnings

See `services/mcp-memory-bridge/README.md` for detailed setup.

---

## X/Twitter Integration

Two complementary services handle X presence:

| Service | Interval | Purpose |
|---------|----------|---------|
| `x-watcher` | 15 min | Polls for mentions via bird CLI, writes sense events |
| `x-engage` | 15 min | Proactive posting (original content every 4+ hours) |

### Architecture

- `bird` CLI (github.com/steipete/bird) handles all posting and mention checking
- `x-watcher` detects mentions and creates sense events for Samara to process
- `x-engage` independently posts proactive content using Claude (Haiku) for generation

### Scripts

- `x-engage` — Proactive posting (generates content via Claude, posts via bird)
- `x-check` — CLI-based mention checking (legacy, rarely used)
- `x-post` — Simple posting wrapper (uses bird CLI)

### State files

- `~/.claude-mind/state/x-watcher-state.json` — Tracks seen tweet IDs
- `~/.claude-mind/state/x-engage-state.json` — Tracks last proactive post time

### SenseRouter Integration

`handleXEvent()` in `SenseRouter.swift` processes X sense events with memory search and reply capabilities.

### launchd services

```bash
# Check status
launchctl list | grep -E "(x-watcher|x-engage)"

# Load services
launchctl load ~/Library/LaunchAgents/com.claude.x-watcher.plist
launchctl load ~/Library/LaunchAgents/com.claude.x-engage.plist
```

---

## Wallet Awareness (Phase 7)

Monitors Solana, Ethereum, and Bitcoin wallet balances and transactions.

### Wallets

| Chain | Address |
|-------|---------|
| Solana | `8oyD1P9Kdu4ZkC78q39uvEifAqQv26sULnjoKsHzJe6C` |
| Ethereum | `0xE74E61C5e9beE3f989824A20e138f9aAE16f41Ad` |
| Bitcoin | `bc1qu9m98ae7nf5z599ah8hev8xyuf7alr0ntskhwn` |

### How it works

- Polls public RPC endpoints every 15 minutes (no API keys required)
- Compares current balance to previous state
- Writes SenseEvent when significant changes detected
- Priority: `immediate` for deposits >$100 or any withdrawal, `normal` for smaller deposits

### Scripts

- `wallet-status` — Display current balances and addresses

### Skill

- `/wallet` — Check balances, addresses, or recent history

### Files

- `~/.claude-mind/credentials/wallet-apis.json` — RPC endpoints and addresses
- `~/.claude-mind/state/wallet-state.json` — Tracked balances and last seen transactions
- `services/wallet-watcher/server.py` — Polling service

### launchd service

```bash
# Check status
launchctl list | grep wallet

# Load service
launchctl load ~/Library/LaunchAgents/com.claude.wallet-watcher.plist
```

### Current limitations

- Read-only (no transaction signing yet)
- USD estimates use hardcoded prices, not live market data
- No token tracking (native assets only)
