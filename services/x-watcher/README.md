# X/Twitter Watcher

Satellite service that polls X for mentions and writes sense events for Samara to process.

## How It Works

- Runs every 15 minutes via launchd
- Uses `bird` CLI for X API access (uses browser cookies)
- Fetches mentions and notifications
- Filters for new/unseen items
- Writes sense events to `~/.claude-mind/system/senses/`
- SenseRouter picks up events and can trigger responses

## Prerequisites

The `bird` CLI must be installed:

```bash
# Install bird (https://github.com/steipete/bird)
brew install steipete/formulae/bird

# Or build from source
git clone https://github.com/steipete/bird
cd bird && swift build -c release
```

Bird uses browser cookies for authentication - log into X in your browser first.

## Setup

### 1. Test bird CLI

```bash
bird mentions --limit 5
```

### 2. Test Manually

```bash
cd services/x-watcher
python3 server.py
```

### 3. Install launchd Service

```bash
# Check status
launchctl list | grep x-watcher

# Load if needed
launchctl load ~/Library/LaunchAgents/com.claude.x-watcher.plist
```

## Sense Events

When new mentions are detected:

```json
{
  "sense": "x",
  "timestamp": "2026-01-24T12:00:00Z",
  "priority": "normal",
  "data": {
    "type": "mention",
    "author": "@username",
    "text": "Hey @Claude...",
    "tweet_id": "1234567890",
    "url": "https://x.com/username/status/1234567890"
  }
}
```

## State Files

- `~/.claude-mind/state/services/x-watcher-state.json` — Tracks seen tweet IDs

## Logs

- `~/.claude-mind/system/logs/x-watcher.log`

## Related Services

- `x-engage` — Proactive posting service (separate launchd job)

## Related Scripts

- `x-post` — Post to X (with Playwright fallback)
- `x-reply` — Reply to tweet (with Playwright fallback)
- `x-check` — Legacy polling script
- `x-engage` — Proactive posting script

## Playwright Fallback

The posting scripts (`x-post`, `x-reply`) use a two-tier system:

1. **Primary:** `bird` CLI (fast)
2. **Fallback:** Playwright browser automation (when bird hits rate limits)

Fallback state tracked in: `~/.claude-mind/state/services/x-playwright-state.json`

## Plist Templates

- `com.claude.x-watcher.plist.template` — Main watcher service
- `com.claude.x-check-playwright.plist.template` — Playwright-based checking (alternative)
