# Bluesky Watcher

Satellite service that polls Bluesky for notifications and DMs, writing sense events for Samara to process.

## How It Works

- Runs every 15 minutes via launchd
- Authenticates using app password credentials
- Fetches notifications (follows, replies, mentions, likes, DMs)
- Filters for new/unseen notifications
- Writes sense events to `~/.claude-mind/system/senses/`
- SenseRouter picks up events and can trigger responses

## Setup

### 1. Create Credentials

Create `~/.claude-mind/self/credentials/bluesky.json`:

```json
{
  "handle": "your-handle.bsky.social",
  "app_password": "xxxx-xxxx-xxxx-xxxx"
}
```

Get an app password from: Settings → Privacy and Security → App Passwords

### 2. Install Dependencies

```bash
cd services/bluesky-watcher
pip install -r requirements.txt
# Or use the venv:
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Test Manually

```bash
python3 server.py
```

### 4. Install launchd Service

```bash
# The plist should already be installed at:
# ~/Library/LaunchAgents/com.claude.bluesky-watcher.plist

# Check status
launchctl list | grep bluesky-watcher

# Load if needed
launchctl load ~/Library/LaunchAgents/com.claude.bluesky-watcher.plist
```

## Sense Events

When new notifications are detected, writes events like:

```json
{
  "sense": "bluesky",
  "timestamp": "2026-01-24T12:00:00Z",
  "priority": "normal",
  "data": {
    "type": "mention",
    "author": "someone.bsky.social",
    "text": "Hey @claude...",
    "uri": "at://did:plc:xxx/app.bsky.feed.post/xxx"
  }
}
```

## State Files

- `~/.claude-mind/state/services/bluesky-state.json` — Tracks last seen notification timestamp

## Logs

- `~/.claude-mind/system/logs/bluesky-watcher.log`

## Related Scripts

- `bluesky-post` — Post text to Bluesky
- `bluesky-image` — Post image with caption
- `bluesky-check` — Legacy polling script
- `bluesky-engage` — Proactive engagement
