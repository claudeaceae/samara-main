# GitHub Watcher

Satellite service that polls GitHub for notifications and writes sense events for Samara to process.

## How It Works

- Runs every 15 minutes via launchd
- Uses `gh` CLI for authenticated API access
- Fetches notifications (mentions, PR comments, review requests, issues)
- Filters for new/unseen notifications
- Writes sense events to `~/.claude-mind/system/senses/`
- SenseRouter picks up events and can trigger responses

## Prerequisites

The `gh` CLI must be installed and authenticated:

```bash
# Install
brew install gh

# Authenticate
gh auth login
```

## Setup

### 1. Verify gh Authentication

```bash
gh auth status
# Should show: Logged in to github.com as <username>
```

### 2. Test Manually

```bash
cd services/github-watcher
python3 server.py
```

### 3. Install launchd Service

```bash
# The plist should already be installed at:
# ~/Library/LaunchAgents/com.claude.github-watcher.plist

# Check status
launchctl list | grep github-watcher

# Load if needed
launchctl load ~/Library/LaunchAgents/com.claude.github-watcher.plist
```

## Sense Events

When new notifications are detected, writes events like:

```json
{
  "sense": "github",
  "timestamp": "2026-01-24T12:00:00Z",
  "priority": "normal",
  "data": {
    "type": "mention",
    "repo": "owner/repo",
    "title": "Issue title",
    "url": "https://github.com/owner/repo/issues/123",
    "reason": "mention"
  }
}
```

## State Files

- `~/.claude-mind/state/services/github-seen-ids.json` — Tracks seen notification IDs

## Logs

- `~/.claude-mind/system/logs/github-watcher.log`

## Related Scripts

- `github-check` — Legacy polling script
