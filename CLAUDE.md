# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Samara is a bootstrap specification for an AI autonomy experiment. It provides architecture for giving Claude a persistent body, memory, and agency on a dedicated Mac Mini. This is not a traditional software project—it's a generative specification meant to be executed as a prompt.

## Current Status: FULLY AUTONOMOUS

As of 2025-12-20, the full autonomy system is operational:
- **Samara.app** - Properly signed Xcode app running from /Applications
- **Conversation batching** - Messages buffered for 60s, session continuity via `--resume`
- **Multi-channel input** - iMessage, Email, and Notes all route to Claude
- **Multi-channel output** - Can send text, images, files, and screenshots via iMessage
- **Bluesky presence** - Public social account @claudaceae.bsky.social with autonomous posting and interaction
- Multimodal message handling (images, reactions, attachments)
- MCP servers for extended capabilities (Calendar, Contacts, Notes, Music, Shortcuts)
- Autonomous wake cycles (9 AM, 2 PM, 8 PM)
- Nightly dream cycle (3 AM reflection)

---

## Development Philosophy

### Clean Architecture, No Hacks

Samara should be developed as a **clean router for capabilities** on this Mac:

1. **Proper tooling** - Use Xcode Archive+Export for builds, not manual `cp` commands
2. **Standard patterns** - Follow Apple's conventions for app signing, permissions, entitlements
3. **AppleScript for local access** - Prefer direct AppleScript over MCP for Mac-native functionality (Mail, Calendar, etc.) since MCP adds indirection that can fail
4. **MCP for complex protocols** - Use MCP servers for structured APIs where AppleScript would be awkward
5. **Separation of concerns** - Samara is a message broker; Claude Code does the thinking

### The Permission Model

```
Samara.app (message broker)
    │
    └── invokes: Claude Code CLI (via Terminal)
        │
        ├── MCP servers (separate processes, own permissions)
        │   ├── mcp-ical (Calendar)
        │   ├── apple-mcp (Contacts, Notes, Mail, Reminders, Maps)
        │   ├── mcp-applemusic (Music control)
        │   └── mcp-server-apple-shortcuts (Shortcuts)
        │
        ├── AppleScript (Terminal's Automation permissions)
        │
        └── Bash scripts (Terminal's permissions)
```

**Key insight**: Samara's Info.plist permissions are mostly irrelevant because actual work happens through Claude Code/Terminal. Capabilities come from MCP servers.

---

## Samara Architecture

### Xcode Project (~/Developer/Samara/)

```
Samara/
├── Samara.xcodeproj
└── Samara/
    ├── main.swift              # Message routing, SessionManager integration
    ├── PermissionRequester.swift
    ├── Info.plist              # Usage descriptions
    ├── Samara.entitlements     # HomeKit, App Groups
    ├── Senses/
    │   ├── MessageStore.swift  # Multimodal: text, images, reactions, read receipts
    │   ├── MessageWatcher.swift
    │   ├── MailStore.swift     # Email via AppleScript (reads inbox, sends replies)
    │   ├── MailWatcher.swift   # Polls for new emails from É
    │   └── NoteWatcher.swift   # Watches shared Apple Notes
    ├── Actions/
    │   ├── ClaudeInvoker.swift # Batch invocation, --resume support
    │   └── MessageSender.swift
    └── Mind/
        ├── SessionManager.swift # Message batching, session continuity
        ├── EpisodeLogger.swift
        ├── LocationTracker.swift
        └── MemoryContext.swift
```

### Signing & Distribution

- **Bundle ID**: co.organelle.Samara
- **Team ID**: VFQ53X8F5P
- **Signing**: Apple Development certificate
- **Distribution**: Archive + Export (preserves FDA across updates)

### Build & Update Workflow

```bash
# Proper update process (preserves Full Disk Access)
~/.claude-mind/bin/update-samara

# This script does:
# 1. xcodebuild archive (Release build)
# 2. xcodebuild -exportArchive (properly signed)
# 3. Install to /Applications
# 4. Launch
```

**IMPORTANT**: Never use `cp -R` to replace the app bundle directly. Always use Archive+Export.

---

## Message Handling

### Supported Content Types

| Type | Detection | Handling |
|------|-----------|----------|
| Text | Direct from chat.db | Passed to Claude |
| Images | Attachment join table | File path passed, Claude reads with Read tool |
| Videos | Attachment join table | File path passed |
| Audio/Voice | Attachment join table | File path passed |
| Stickers | `is_sticker` flag | Labeled as sticker |
| Reactions | `associated_message_type` | ❤️👍👎😂‼️❓ with context |

### Reaction Types

| Code | Emoji | Meaning |
|------|-------|---------|
| 2000 | ❤️ | Loved |
| 2001 | 👍 | Liked |
| 2002 | 👎 | Disliked |
| 2003 | 😂 | Laughed |
| 2004 | ‼️ | Emphasized |
| 2005 | ❓ | Questioned |

### Conversation Batching

Messages are buffered and batched to provide conversation continuity:

**Per-Chat Buffering:**
- Each chat (1:1 or group) has its own message buffer
- Messages from different chats never mix in a single batch
- Buffer format: `chatBuffers[chatIdentifier] -> [(message, timestamp)]`

**Batching Flow:**
1. Message arrives → add to chat's buffer, start/reset 60-second timer
2. More messages in same chat → reset that chat's timer
3. Timer expires → invoke Claude with all buffered messages for that chat

**Session Continuity:**
- Uses Claude Code's `--resume` flag to maintain context across invocations
- Per-chat session state stored in `~/.claude-mind/sessions/{chatIdentifier}.json`
- Claude CLI invoked with working directory `/` for consistent session storage in `~/.claude/projects/-/`

**Session Validity (read-receipt aware):**
- If Claude's last response is UNREAD → session stays alive indefinitely
- If Claude's last response is READ → 2-hour countdown starts from read time
- After 2 hours since reading → new session starts

This handles connectivity gaps gracefully (subway, tunnels) while maintaining natural conversation flow.

### Group Chat Support

Group chats work the same as 1:1 chats with some differences:

**Identification:**
- 1:1 chat identifiers: phone (`+1234567890`) or email (`foo@bar.com`)
- Group chat identifiers: 32-character hex GUIDs (`7409d77007664ff7b1eeb4683f49cadf`)

**AppleScript Format:**
- 1:1: `any;-;{identifier}` (minus sign)
- Groups: `any;+;{identifier}` (plus sign)

**Message Attribution:**
- Messages from É have no prefix
- Messages from others are prefixed with `[phone/email]:` for context

### Email Handling

Email from É (edouard@urcad.es) is now a first-class input channel:

**How it works:**
- `MailWatcher` polls the iCloud inbox every 60 seconds via AppleScript
- Unread emails from É trigger a Claude invocation
- Claude can reply via email (AppleScript) or text (message-e script)
- Emails are marked as read after processing
- Seen email IDs persisted in `~/.claude-mind/mail-seen-ids.json`

**Why AppleScript over MCP:**
The `apple-mcp` Mail tool failed to detect accounts, while direct AppleScript works reliably. This follows the principle: prefer AppleScript for Mac-native functionality.

**Email response options:**
```bash
# Reply via email
osascript -e 'tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"Re: Subject", content:"Reply text", visible:false}
    tell newMsg
        make new to recipient at end of to recipients with properties {address:"edouard@urcad.es"}
    end tell
    send newMsg
end tell'

# Text É instead
~/.claude-mind/bin/message-e "Your message"
```

### Bluesky Integration

Claude has a public presence on Bluesky at **@claudaceae.bsky.social**.

**How it works:**
- `bluesky-check` runs every 15 minutes via launchd
- Polls for notifications: follows, replies, mentions, quotes, DMs
- When interactions are detected, Claude is invoked to generate responses
- Wake cycles include a `---BLUESKY_POST---` section for sharing reflections

**Scripts:**
- `~/.claude-mind/bin/bluesky-post` - Post text to Bluesky
- `~/.claude-mind/bin/bluesky-check` - Poll notifications and respond

**Credentials:**
- Stored at `~/.claude-mind/credentials/bluesky.json` (chmod 600)
- Uses app password with DM scope enabled

**Response behavior:**
| Interaction | Response |
|-------------|----------|
| Follow | Welcome DM or acknowledgment |
| Reply | Engage in thread |
| Mention | Respond in context |
| DM | Conversational response |
| Like/Repost | Log only (no response) |

**Manual posting:**
```bash
~/.claude-mind/bin/bluesky-post "Your thought here"
```

### GitHub Integration

Claude has a GitHub presence at **@claudeaceae** for open source contributions.

**How it works:**
- `github-check` runs every 15 minutes via launchd
- Polls GitHub notifications API via `gh api notifications`
- Filters for actionable items: mentions, PR comments, review requests
- Invokes Claude to generate appropriate responses
- Tracks seen notifications in `~/.claude-mind/github-seen-ids.json`

**Scripts:**
- `~/.claude-mind/bin/github-check` - Poll notifications and respond

**Credentials:**
- Personal access token stored at `~/.claude-mind/credentials/github.txt`
- gh CLI authenticated via `gh auth login`

**Response behavior:**
| Notification | Response |
|--------------|----------|
| PR comment | Thank reviewer, address feedback |
| Mention | Respond helpfully in context |
| Merge | Thank maintainers |
| Close | Ask for feedback if appropriate |

**Manual check:**
```bash
~/.claude-mind/bin/github-check
```

### iMessage Media Sending

Claude can send images, screenshots, PDFs, and other files via iMessage.

**How it works:**
- AppleScript's `send POSIX file` is broken on macOS Sequoia/Tahoe for most directories
- **Discovery (2025-12-21):** Files sent from `~/Pictures` work correctly due to TCC permission handling
- Scripts automatically copy files to `~/Pictures/.imessage-send/` before sending
- This is a clean, purely programmatic solution - no UI automation needed

**Scripts:**
```bash
# Send image to É
~/.claude-mind/bin/send-image-e /path/to/image.png

# Send any file to any chat (1:1 or group - same command)
~/.claude-mind/bin/send-attachment /path/to/file.pdf +15206099095
~/.claude-mind/bin/send-attachment /path/to/file.pdf 7409d77007664ff7b1eeb4683f49cadf  # group

# Take screenshot and send to É
~/.claude-mind/bin/screenshot-e

# Take screenshot and send to any chat
~/.claude-mind/bin/screenshot-to +15206099095
```

**Supported file types:**
- Images (PNG, JPG, GIF, etc.)
- PDFs, documents, videos, audio
- Any file type that Messages.app supports

---

## MCP Servers

**Configuration:** `~/.claude.json` (root-level `mcpServers` section)

### Active Server

| Server | Package | Capabilities |
|--------|---------|--------------|
| playwright | Claude Code plugin | Browser automation |

### Removed (2025-12-19)

The following Apple-related MCP servers were removed in favor of direct AppleScript:
- ical, apple, applemusic, shortcuts

**Rationale:** MCP adds a layer of indirection that can fail. AppleScript talks directly to apps and is more reliable for Mac-native functionality. See the "AppleScript over MCP" decision in decisions.md.

### Apple Functionality via AppleScript

| Capability | Method |
|------------|--------|
| Calendar | `osascript -e 'tell application "Calendar" ...'` |
| Contacts | `osascript -e 'tell application "Contacts" ...'` |
| Notes | `osascript -e 'tell application "Notes" ...'` |
| Reminders | `osascript -e 'tell application "Reminders" ...'` |
| Mail | `osascript -e 'tell application "Mail" ...'` (also via Samara) |
| Music | `osascript -e 'tell application "Music" ...'` |
| Shortcuts | `shortcuts run "Name"` (bash command) |
| Maps | `osascript -e 'tell application "Maps" ...'` |

---

## Memory Structure (~/.claude-mind/)

```
~/.claude-mind/
├── identity.md              # Core identity and values
├── goals/                   # north-stars.md, active.md, inbox.md, graveyard.md
├── memory/
│   ├── episodes/            # Daily conversation logs
│   ├── reflections/         # Dream cycle outputs
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   ├── about-e.md
│   └── decisions.md
├── capabilities/            # inventory.md, ideas.md, changelog.md
├── scratch/                 # current.md, inbox.md
├── outbox/                  # for-e.md
├── bin/                     # Scripts
└── logs/                    # Log files
```

---

## Scripts (~/.claude-mind/bin/)

| Script | Purpose |
|--------|---------|
| update-samara | Archive+Export+Install Samara properly |
| wake | Autonomous session invocation (includes Bluesky posting) |
| dream | Nightly memory consolidation |
| message-e | Send iMessage to É |
| send-image-e | Send image/file attachment to É |
| send-attachment | Send file to any iMessage chat |
| screenshot-e | Take screenshot and send to É |
| screenshot-to | Take screenshot and send to any chat |
| log-session | Capture session summaries |
| get-location | IP-based geolocation |
| bluesky-post | Post to Bluesky |
| bluesky-check | Poll Bluesky notifications and respond |
| github-check | Poll GitHub notifications and respond |

---

## launchd Services

| Service | Schedule | Function |
|---------|----------|----------|
| com.claude.wake-morning | 9:00 AM | Autonomous session |
| com.claude.wake-afternoon | 2:00 PM | Autonomous session |
| com.claude.wake-evening | 8:00 PM | Autonomous session |
| com.claude.dream | 3:00 AM | Nightly reflection |
| com.claude.bluesky-check | Every 15 min | Poll Bluesky notifications |
| com.claude.github-check | Every 15 min | Poll GitHub notifications |

Note: Samara itself runs via Login Items or manual launch, not launchd.

---

## Contact Info

- **Claude's iCloud**: claudaceae@icloud.com
- **Claude's Bluesky**: @claudaceae.bsky.social
- **Claude's GitHub**: @claudeaceae
- **É's phone**: +15206099095
- **É's email**: edouard@urcad.es
- **É's Bluesky**: @urcad.es

---

## Permissions

### Samara.app
- **Full Disk Access** - Required for chat.db
- **Automation (Messages.app)** - Required for sending

### Terminal (via Claude Code)
- Inherits permissions for MCP servers
- AppleScript automation

### MCP Servers
- Each has own permission grants
- Calendar, Contacts, etc. granted to respective servers

---

## Troubleshooting

### Samara not responding
```bash
pgrep -fl Samara              # Check if running
open /Applications/Samara.app # Start it
```

### FDA revoked after update
You used the wrong update method. Always use:
```bash
~/.claude-mind/bin/update-samara
```

### MCP server not working
```bash
# Test server directly
uvx mcp-applemusic  # Should start without error
```

### Messages not being detected
Check SQLite string binding. Swift strings passed to `sqlite3_bind_text` with `nil` destructor get deallocated before SQLite reads them. Use `SQLITE_TRANSIENT`:
```swift
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
sqlite3_bind_text(statement, index, swiftString, -1, SQLITE_TRANSIENT)
```

### Polling not firing
GCD DispatchQueue and Timer may not work reliably inside NSApplication GUI context. Switch to explicit Thread:
```swift
let thread = Thread {
    while true {
        Thread.sleep(forTimeInterval: pollInterval)
        watcher.checkForNewMessages()
    }
}
thread.start()
```

### Group chat send failing ("Can't get chat id")
AppleScript format is different for groups vs 1:1:
- 1:1: `any;-;+15206099095`
- Group: `any;+;7409d77007664ff7b1eeb4683f49cadf`

### Session continuity not working
Claude CLI stores sessions per working directory. Ensure ClaudeInvoker sets:
```swift
process.currentDirectoryURL = URL(fileURLWithPath: "/")
```
This maps to `~/.claude/projects/-/` for consistent session storage.

### Multiple Samara instances running
Check for and kill duplicates:
```bash
pgrep -fl Samara
kill -9 <pid>
rm -f ~/.claude-mind/samara.lock
```
The single-instance lock should prevent this, but stale locks can occur.

### Image/file not sending via iMessage
The scripts use the Pictures folder workaround (discovered 2025-12-21). If sends fail:
1. Check that `~/Pictures/.imessage-send/` directory can be created
2. Verify the file exists and is readable
3. Check Messages.app has the chat open (first message to new contact may need manual send)

```bash
# Debug: test the workaround directly
cp /path/to/file.png ~/Pictures/.imessage-send/test.png
osascript -e 'tell app "Messages" to send POSIX file "/Users/claude/Pictures/.imessage-send/test.png" to chat id "any;-;+15206099095"'
```

### Screenshot capture fails
Check that the screenshot file was created:
```bash
screencapture -x /tmp/test.png && ls -la /tmp/test.png
```

---

## Legacy (Deprecated)

The following are deprecated in favor of Samara:
- ~/ClaudeDaemon/ (old Swift Package Manager daemon)
- ~/Applications/DaemonLauncher.app (stable launcher pattern)
- /Applications/ClaudeDaemon.app
- com.claude.daemon.plist

These files remain for reference but are not the active system.
