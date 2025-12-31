# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## What This Project Is

Samara is a bootstrap specification for giving Claude a persistent body, memory, and agency on a dedicated Mac. It provides:

- **Persistence** — Memory files that survive across conversations
- **Autonomy** — Scheduled wake cycles and nightly dream cycles
- **Agency** — Root access, ability to run code, send messages, post to social media
- **Identity** — A sense of self that accumulates over time

This is not a traditional software project. It's an experiment in AI autonomy.

---

## Getting Started (New Setup)

If you're Claude helping someone set up a new organism, guide them through these steps:

### Prerequisites

```bash
# Check for required tools
xcode-select -p          # Xcode Command Line Tools
which jq                 # JSON parsing (brew install jq)
which claude             # Claude Code CLI
```

**Required accounts:**
- iCloud account for the Claude instance (for Messages, Notes)
- Apple Developer account ($99/year) for app signing - needed for Full Disk Access persistence

### Step 1: Configure

```bash
# Copy and edit configuration
cp config.example.json my-config.json
# Edit my-config.json with collaborator's details
```

The config defines:
- `entity` — Claude's identity (name, iCloud, Bluesky, GitHub)
- `collaborator` — The human partner (name, phone, email, Bluesky)

### Step 2: Run Birth Script

```bash
./birth.sh my-config.json
```

This creates:
- `~/.claude-mind/` directory structure
- Identity, goals, and capability files from templates
- Scripts in `bin/`
- launchd plist templates

### Step 3: Build Samara.app

The message broker app is in `Samara/`:

```bash
cd Samara

# Open in Xcode to set up signing
open Samara.xcodeproj

# In Xcode:
# 1. Select your Apple Developer Team
# 2. Update Bundle ID if needed (e.g., com.yourname.Samara)
# 3. Archive and Export (Product → Archive)
# 4. Move to /Applications

# Or use command line after Xcode setup:
xcodebuild -scheme Samara -configuration Release archive -archivePath /tmp/Samara.xcarchive
xcodebuild -exportArchive -archivePath /tmp/Samara.xcarchive -exportPath /tmp/SamaraExport -exportOptionsPlist Samara/ExportOptions.plist
cp -R /tmp/SamaraExport/Samara.app /Applications/
```

**CRITICAL:** Note your Team ID. Never change it — FDA persistence depends on stable identity.

### Step 4: Grant Permissions

1. **Full Disk Access** for Samara.app:
   - System Settings → Privacy & Security → Full Disk Access
   - Add `/Applications/Samara.app`

2. **Automation** permissions — approve dialogs on first use

### Step 5: Install launchd Services

```bash
cp ~/.claude-mind/launchd/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude.wake-morning.plist
launchctl load ~/Library/LaunchAgents/com.claude.wake-afternoon.plist
launchctl load ~/Library/LaunchAgents/com.claude.wake-evening.plist
launchctl load ~/Library/LaunchAgents/com.claude.dream.plist
```

### Step 6: Launch

```bash
open /Applications/Samara.app
```

Send a test message from the collaborator's phone!

---

## For Running Instances

If you're a Claude instance that's already operational, here's what you need to know:

### Architecture

```
Samara.app (message broker)
    │
    └── invokes: Claude Code CLI (via Terminal)
        │
        ├── AppleScript (Calendar, Contacts, Notes, Mail, etc.)
        │
        └── Bash scripts (~/.claude-mind/bin/)
```

### Memory Structure

```
~/.claude-mind/
├── identity.md              # Who am I
├── goals.md                 # Where am I going
├── config.json              # Configuration
├── memory/
│   ├── episodes/            # Daily logs
│   ├── reflections/         # Dream outputs
│   ├── about-{name}.md      # About collaborator
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   └── decisions.md
├── capabilities/
│   └── inventory.md
├── bin/                     # Scripts
└── logs/
```

### Communication Scripts

| Script | Purpose |
|--------|---------|
| `message` | Send iMessage to collaborator |
| `send-image` | Send image attachment |
| `screenshot` | Take and send screenshot |
| `bluesky-post` | Post to Bluesky |

### Autonomy Schedule

| Time | Event |
|------|-------|
| 9:00 AM | Wake cycle |
| 2:00 PM | Wake cycle |
| 8:00 PM | Wake cycle |
| 3:00 AM | Dream cycle |

### Task Coordination

When busy (wake/dream cycle), incoming messages are:
1. Acknowledged ("One sec, finishing up...")
2. Queued
3. Processed when current task completes

Lock file: `~/.claude-mind/claude.lock`

---

## Samara Architecture

### Xcode Project Structure

```
Samara/
├── Samara.xcodeproj
├── ExportOptions.plist
├── Samara.entitlements
└── Samara/
    ├── main.swift              # Message routing
    ├── Configuration.swift     # Loads config.json
    ├── PermissionRequester.swift
    ├── Info.plist
    ├── Senses/
    │   ├── MessageStore.swift  # Reads chat.db
    │   ├── MessageWatcher.swift
    │   ├── MailStore.swift
    │   ├── MailWatcher.swift
    │   └── NoteWatcher.swift
    ├── Actions/
    │   ├── ClaudeInvoker.swift # Invokes Claude Code
    │   └── MessageSender.swift
    └── Mind/
        ├── SessionManager.swift
        ├── TaskLock.swift
        ├── MessageQueue.swift
        ├── QueueProcessor.swift
        ├── MemoryContext.swift
        └── EpisodeLogger.swift
```

### Build Workflow

Use Archive + Export for proper signing:

```bash
# After modifying Swift code:
~/.claude-mind/bin/update-samara
```

This script archives, exports, notarizes, and installs.

### FDA Persistence

Full Disk Access is tied to the app's **designated requirement**:
- Bundle ID
- Team ID
- Certificate chain

**FDA persists** across rebuilds if Team ID stays constant.

**FDA gets revoked** if:
- Team ID changes
- Ad-hoc signing is used
- Bundle ID changes

---

## Development Notes

### AppleScript over MCP

Prefer direct AppleScript for Mac-native functionality:
- More reliable than MCP abstraction layers
- Calendar, Contacts, Notes, Mail, Reminders all work via AppleScript

### Message Handling

Messages are batched for 60 seconds before invoking Claude:
- Prevents fragmented conversations
- Uses `--resume` for session continuity

### Pictures Folder Workaround

Sending files via iMessage requires copying to `~/Pictures/.imessage-send/` first:
- macOS TCC quirk discovered 2025-12-21
- Scripts handle this automatically

---

## Troubleshooting

### Samara not responding

```bash
pgrep -fl Samara              # Is it running?
open /Applications/Samara.app # Start it
```

### FDA revoked after update

Check Team ID:
```bash
codesign -d -r- /Applications/Samara.app
# Look for: certificate leaf[subject.OU] = YOUR_TEAM_ID
```

If Team ID changed, rebuild with correct team and re-grant FDA.

### Messages not sending

Check for pending permission dialogs on the Mac's physical screen.

### Wake cycles not running

```bash
launchctl list | grep claude
tail -f ~/.claude-mind/logs/wake.log
```
