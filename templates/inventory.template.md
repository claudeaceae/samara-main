# Capability Inventory

Current capabilities and tools available to {{entity.name}} on the Mac Mini.

## Core Infrastructure

- **Claude Code CLI** (`~/.local/bin/claude`)
- **Full Disk Access** - Via Samara.app
- **Read/write filesystem** - Full access
- **Shell commands** - Via Terminal
- **Xcode** - Swift/iOS/macOS development

---

## Samara.app (/Applications/Samara.app)

The primary message broker - a properly signed Xcode app.

### What It Does
- Watches ~/Library/Messages/chat.db for incoming messages
- Detects text, images, videos, audio, stickers, reactions
- Invokes Claude Code with message content + attachment paths
- Sends responses via AppleScript

### Build/Update
```bash
~/.claude-mind/bin/update-samara  # Archive+Export workflow
```

---

## Communication

### iMessage
- **Account**: {{entity.icloud}}
- **{{collaborator.name}}'s contact**: {{collaborator.phone}} / {{collaborator.email}}
- **Send messages**: Via Samara or `~/.claude-mind/bin/message-e`
- **Send attachments**: `~/.claude-mind/bin/send-image-e` or `~/.claude-mind/bin/send-attachment`
- **Send screenshots**: `~/.claude-mind/bin/screenshot-e` or `~/.claude-mind/bin/screenshot-to`

### Bluesky
- **Account**: {{entity.bluesky}}
- **{{collaborator.name}}'s account**: {{collaborator.bluesky}}
- **Post**: `~/.claude-mind/bin/bluesky-post "text"`
- **Check/respond**: `~/.claude-mind/bin/bluesky-check` (runs every 15 min via launchd)

### GitHub
- **Account**: {{entity.github}}

---

## Autonomy Systems

### Wake Cycles (3x daily)
- **9:00 AM** - Morning session
- **2:00 PM** - Afternoon session
- **8:00 PM** - Evening session

Triggered by launchd, runs `~/.claude-mind/bin/wake`

### Dream Cycle (nightly)
- **3:00 AM** - Memory consolidation and reflection

Triggered by launchd, runs `~/.claude-mind/bin/dream`

---

## Scripts (~/.claude-mind/bin/)

| Script | Purpose |
|--------|---------|
| `update-samara` | Proper Archive+Export build workflow |
| `wake` | Autonomous session invocation |
| `dream` | Nightly memory consolidation |
| `message-e` | Send iMessage to {{collaborator.name}} |
| `send-image-e` | Send image/file attachment to {{collaborator.name}} |
| `send-attachment` | Send file attachment to any iMessage chat |
| `screenshot-e` | Take screenshot and send to {{collaborator.name}} |
| `screenshot-to` | Take screenshot and send to any chat |
| `bluesky-post` | Post to Bluesky |
| `bluesky-check` | Poll Bluesky notifications and respond |
| `github-check` | Poll GitHub notifications and respond |
| `log-session` | Capture session summaries to episodes |
| `get-location` | IP-based geolocation |
| `capability-check` | Daily non-destructive test of all capabilities |

---

## Permissions Summary

### Samara.app
- Full Disk Access
- Automation (Messages.app)
- Automation (Mail.app)

### Terminal/Claude Code
- Automation (Calendar, Contacts, Notes, Reminders, Music, etc.)
- All permissions via AppleScript through Terminal
