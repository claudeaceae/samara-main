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
- Routes sense events from background services

### Build/Update
```bash
~/.claude-mind/system/bin/update-samara  # Archive+Export workflow
```

---

## Communication

### iMessage
- **Account**: {{entity.icloud}}
- **{{collaborator.name}}'s contact**: {{collaborator.phone}} / {{collaborator.email}}
- **Send messages**: Via Samara or `~/.claude-mind/system/bin/message-e`
- **Send attachments**: `~/.claude-mind/system/bin/send-image` or `~/.claude-mind/system/bin/send-attachment`
- **Send screenshots**: `~/.claude-mind/system/bin/screenshot-e` or `~/.claude-mind/system/bin/screenshot-to`

### Bluesky
- **Account**: {{entity.bluesky}}
- **{{collaborator.name}}'s account**: {{collaborator.bluesky}}
- **Post**: `~/.claude-mind/system/bin/bluesky-post "text"`
- **Check/respond**: Via `bluesky-watcher` service (every 15 min)

### X/Twitter
- **Account**: {{entity.x}}
- **{{collaborator.name}}'s account**: {{collaborator.x}}
- **Check/respond**: Via `x-watcher` service (every 15 min)

### GitHub
- **Account**: {{entity.github}}
- **Check notifications**: Via `github-watcher` service (every 15 min)

### Email
- **Account**: {{mail.account}}
- **Check/send**: Via AppleScript automation

---

## Services (Background)

Services run via launchd and extend capabilities through polling and HTTP endpoints.

| Service | Type | Purpose |
|---------|------|---------|
| `location-receiver` | HTTP (8081) | Receives GPS from Overland app |
| `webhook-receiver` | HTTP (8082) | Receives webhooks (GitHub, IFTTT) |
| `mcp-memory-bridge` | HTTP (8765) | Shared memory for Claude Desktop/Web |
| `bluesky-watcher` | Poller | Polls Bluesky notifications |
| `github-watcher` | Poller | Polls GitHub notifications |
| `x-watcher` | Poller | Polls X/Twitter mentions |
| `wallet-watcher` | Poller | Monitors crypto wallet balances |
| `meeting-check` | Poller | Detects meetings for prep/debrief |
| `wake-scheduler` | CLI | Calculates adaptive wake times |

See `services/README.md` for details.

---

## Autonomy Systems

### Adaptive Wake Scheduler
- **~9 AM** - Morning session (base schedule)
- **~2 PM** - Afternoon session (base schedule)
- **~8 PM** - Evening session (base schedule)
- **Adaptive** - Early wakes for calendar events, priority items

Triggered every 15 min by `wake-adaptive`, which consults `wake-scheduler`

### Dream Cycle (nightly)
- **3:00 AM** - Memory consolidation and reflection

Triggered by launchd, runs `~/.claude-mind/system/bin/dream`

---

## Key Scripts (~/.claude-mind/system/bin/)

| Script | Purpose |
|--------|---------|
| `update-samara` | Proper Archive+Export build workflow |
| `wake` | Autonomous session invocation |
| `dream` | Nightly memory consolidation |
| `message-e` | Send iMessage to {{collaborator.name}} |
| `send-image` | Send image/file attachment |
| `send-attachment` | Send file attachment to any chat |
| `screenshot-e` | Take screenshot and send to {{collaborator.name}} |
| `bluesky-post` | Post to Bluesky |
| `generate-image` | Generate images via AI |
| `search-memory` | Semantic search across memory |
| `log-session` | Capture session summaries to episodes |
| `get-location` | IP-based geolocation |

See `scripts/README.md` for full catalog (~90 scripts).

---

## Memory Systems

### Semantic Search
- **Chroma database**: `~/.claude-mind/memory/chroma/`
- **Search tool**: `~/.claude-mind/system/bin/search-memory`
- **Embedded content**: Learnings, observations, decisions, reflections

### Episode Logging
- **Daily episodes**: `~/.claude-mind/memory/episodes/YYYY/MM/DD.md`
- **Session summaries**: Appended via `log-session`

### People Profiles
- **Profiles directory**: `~/.claude-mind/memory/people/`
- **Per-person context**: Relationship, preferences, history

---

## Visual Expression

### Image Generation
- **Script**: `~/.claude-mind/system/bin/generate-image`
- **Avatar reference**: `~/.claude-mind/self/credentials/avatar-ref.png`
- **Mirror poses**: `~/.claude-mind/self/credentials/mirror-refs/`

---

## Permissions Summary

### Samara.app
- Full Disk Access
- Automation (Messages.app)
- Automation (Mail.app)

### Terminal/Claude Code
- Automation (Calendar, Contacts, Notes, Reminders, Music, etc.)
- All permissions via AppleScript through Terminal
