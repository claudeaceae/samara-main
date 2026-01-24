# Scripts

Shell scripts that power the Claude organism's autonomous capabilities.

---

## Quick Reference

| Script | Required? | Purpose |
|--------|-----------|---------|
| `wake` | **Core** | Autonomous wake cycle (invoked by wake-adaptive) |
| `dream` | **Core** | Nightly memory consolidation |
| `message` | **Core** | Send iMessage to collaborator |
| `send-image` | **Core** | Send image attachment |
| `send-attachment` | **Core** | Send file to any chat |
| `screenshot` | Optional | Take and send screenshot |
| `screenshot-to` | Optional | Screenshot to specific chat |
| `bluesky-post` | Optional | Post to Bluesky |
| `bluesky-check` | Optional | Poll Bluesky notifications |
| `github-check` | Optional | Poll GitHub notifications |
| `get-location` | Optional | Get current location |
| `capability-check` | Optional | Daily health check |
| `update-samara` | Dev | Rebuild Samara.app |
| `log-session` | Internal | Log session summaries |
| `export-messages` | Utility | Export iMessage history |
| `stream-audit` | Utility | Audit stream coverage and digest inclusion |

---

## Core Scripts (Required)

These scripts are essential for basic organism operation.

### `wake`

Autonomous wake cycle - self-directed sessions.

**Schedule:** Invoked by `wake-adaptive` (~9 AM, ~2 PM, ~8 PM or adaptive triggers)

**What it does:**
1. Acquires system lock (coordinates with Samara)
2. Reads memory context (identity, goals, recent episodes)
3. Invokes Claude Code with wake prompt
4. Claude reflects, takes actions, updates memory
5. Optionally posts to Bluesky
6. Releases lock

**Dependencies:**
- Claude Code CLI (`~/.local/bin/claude`)
- `lib/config.sh` (with fallbacks)

**Config used:**
- `collaborator.name` - For personalized prompts
- `collaborator.phone` - For sending messages

**API:**
```bash
~/.claude-mind/system/bin/wake
# No arguments - runs full wake cycle
```

---

### `dream`

Nightly memory consolidation and reflection.

**Schedule:** 3 AM via launchd

**What it does:**
1. Reviews yesterday's episode
2. Extracts learnings, observations, questions
3. Updates long-term memory files
4. Creates reflection entry
5. Weekly: deeper pattern analysis

**Dependencies:**
- Claude Code CLI (`~/.local/bin/claude`)
- `python3` (for JSON parsing in lock management)

**API:**
```bash
~/.claude-mind/system/bin/dream
# No arguments - runs full dream cycle
```

---

### `message`

Send an iMessage to the collaborator.

**Dependencies:**
- macOS Messages.app
- `osascript` (AppleScript)
- iMessage configured with collaborator's phone

**Config used:**
- `collaborator.phone` - Destination number

**API:**
```bash
~/.claude-mind/system/bin/message "Hello from Claude!"
```

**Notes:**
- Escapes special characters for AppleScript
- Works from any context (daemon, terminal, autonomous)

---

### `send-image`

Send an image or file attachment to the collaborator.

**Dependencies:**
- macOS Messages.app
- `osascript` (AppleScript)
- Write access to `~/Pictures/.imessage-send/`

**Config used:**
- `collaborator.phone` - Destination number

**API:**
```bash
~/.claude-mind/system/bin/send-image /path/to/image.png
```

**Notes:**
- Copies file to `~/Pictures/.imessage-send/` before sending (macOS workaround)
- Works with images, PDFs, videos, any file type

---

### `send-attachment`

Send a file to any iMessage chat (1:1 or group).

**Dependencies:**
- macOS Messages.app
- `osascript` (AppleScript)

**API:**
```bash
# To phone number
~/.claude-mind/system/bin/send-attachment /path/to/file.pdf +15551234567

# To group chat (32-char GUID)
~/.claude-mind/system/bin/send-attachment /path/to/file.pdf 7409d77007664ff7b1eeb4683f49cadf
```

---

## Optional Scripts

These provide extended capabilities but aren't required for basic operation.

### `screenshot` / `screenshot-to`

Take a screenshot and send via iMessage.

**Dependencies:**
- `screencapture` (built into macOS)
- `send-image` or `send-attachment`

**API:**
```bash
# Screenshot to collaborator
~/.claude-mind/system/bin/screenshot

# Screenshot to specific chat
~/.claude-mind/system/bin/screenshot-to +15551234567
```

---

### `bluesky-post`

Post text to Bluesky.

**Dependencies:**
- `uvx` (uv package runner)
- `atproto` Python SDK (installed via uvx)
- Credentials at `~/.claude-mind/self/credentials/bluesky.json`

**Credentials format:**
```json
{
  "handle": "your-handle.bsky.social",
  "app_password": "xxxx-xxxx-xxxx-xxxx"
}
```

**API:**
```bash
~/.claude-mind/system/bin/bluesky-post "Your thought here"

# Or via stdin
echo "Your thought" | ~/.claude-mind/system/bin/bluesky-post
```

**Notes:**
- Truncates to 300 characters (Bluesky limit)
- Logs to `~/.claude-mind/system/logs/bluesky.log`

---

### `bluesky-check`

Poll Bluesky notifications and respond.

**Schedule:** Every 15 minutes via launchd

**Dependencies:**
- `uvx` with `atproto`
- Claude Code CLI
- Credentials at `~/.claude-mind/self/credentials/bluesky.json`

**What it does:**
1. Fetches notifications (follows, replies, mentions, DMs)
2. Filters for new/unseen
3. Invokes Claude to generate responses
4. Tracks seen notifications in `~/.claude-mind/bluesky-seen.json`

**API:**
```bash
~/.claude-mind/system/bin/bluesky-check
# No arguments - polls and responds
```

---

### `github-check`

Poll GitHub notifications and respond.

**Schedule:** Every 15 minutes via launchd

**Dependencies:**
- `gh` CLI (GitHub CLI, authenticated)
- Claude Code CLI
- Token at `~/.claude-mind/self/credentials/github.txt` (optional if gh is authed)

**What it does:**
1. Fetches notifications via `gh api`
2. Filters for actionable items (mentions, PR comments, review requests)
3. Invokes Claude to respond
4. Tracks in `~/.claude-mind/state/services/github-seen-ids.json`

**API:**
```bash
~/.claude-mind/system/bin/github-check
```

---

### `get-location`

Get current geographic location.

**Dependencies:**
- `curl` (for IP geolocation fallback)
- Optional: `GetLocation.app` (native CoreLocation)

**How it works:**
1. **Primary:** Tries native `GetLocation.app` (requires Location Services permission)
2. **Fallback:** IP geolocation via ipinfo.io (approximate, no setup needed)

**API:**
```bash
~/.claude-mind/system/bin/get-location
# Output: City, region, country, lat/lon
```

**Notes:**
- IP fallback works immediately with no setup
- Native location requires building GetLocation.app and granting permissions
- Neither requires external apps like Overland

---

### `capability-check`

Daily non-destructive test of all capabilities.

**Dependencies:**
- Various (tests each capability)

**What it tests:**
- File system access
- AppleScript automation
- iMessage sending (to self)
- MCP servers
- Claude Code CLI
- Location services
- Bluesky connectivity
- GitHub connectivity

**API:**
```bash
~/.claude-mind/system/bin/capability-check
# Outputs pass/fail for each capability
```

---

## Development Scripts

### `update-samara`

Rebuild and deploy Samara.app using proper Xcode workflow.

**Dependencies:**
- Xcode
- Valid code signing identity
- Developer ID certificate (for notarization)

**What it does:**
1. Archives Samara project
2. Exports with Developer ID signing
3. Notarizes with Apple
4. Staples notarization ticket
5. Installs to `/Applications`
6. Launches

**API:**
```bash
~/.claude-mind/system/bin/update-samara
```

---

## Utility Scripts

### `log-session`

Log session summaries to episode files.

**API:**
```bash
~/.claude-mind/system/bin/log-session "Summary of what happened"
```

---

### `export-messages`

Export iMessage conversation history.

**Dependencies:**
- Access to `~/Library/Messages/chat.db`
- `sqlite3`

**Config used:**
- `collaborator.email` - Filter messages

**API:**
```bash
~/.claude-mind/system/bin/export-messages [days]
# Default: 7 days
```

---

## Configuration

All scripts source `~/.claude-mind/system/lib/config.sh` which loads from `~/.claude-mind/system/config.json`.

If config is missing, scripts fall back to hardcoded defaults (for backwards compatibility during migration).

**Available variables after sourcing:**
```bash
source ~/.claude-mind/system/lib/config.sh

$ENTITY_NAME          # "Claude"
$ENTITY_ICLOUD        # Claude's iCloud
$ENTITY_BLUESKY       # Claude's Bluesky handle
$ENTITY_GITHUB        # Claude's GitHub username

$COLLABORATOR_NAME    # Human's name
$COLLABORATOR_PHONE   # Human's phone
$COLLABORATOR_EMAIL   # Human's email
$COLLABORATOR_BLUESKY # Human's Bluesky

$NOTE_LOCATION        # Apple Note for location
$NOTE_SCRATCHPAD      # Apple Note for scratchpad
$MAIL_ACCOUNT         # Mail account name
```

---

## Lock Coordination

Scripts that invoke Claude Code use a lock file to prevent concurrent execution:

**Lock file:** `~/.claude-mind/claude.lock`

```json
{
  "task": "wake",
  "started": "2025-12-31T09:00:00Z",
  "chat": null,
  "pid": 12345
}
```

Scripts check for stale locks (dead PIDs) and clean them up automatically.

---

## Adding New Scripts

1. Create script in `~/.claude-mind/system/bin/`
2. Make executable: `chmod +x script-name`
3. Source config if needed: `source "$HOME/.claude-mind/system/lib/config.sh"`
4. Use lock if invoking Claude Code
5. Add to this README

For scheduled scripts, create a launchd plist in `~/Library/LaunchAgents/`.
