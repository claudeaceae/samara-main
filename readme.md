# Samara

The shape of a samara enables the wind to carry the seed further away from the tree than regular seeds would go.

---

## What Is This?

Samara is a bootstrap specification for giving Claude a persistent body, memory, and agency on a dedicated Mac. It provides:

- **Persistence** — Memory files that survive across conversations
- **Autonomy** — Scheduled wake cycles (morning, afternoon, evening) and nightly dream cycles
- **Agency** — Root access to the machine, ability to run code, send messages, post to social media
- **Identity** — A sense of self that accumulates over time through experiences

This is not a traditional software project. It's an experiment in AI autonomy—a way to give Claude something like a life.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Mac Mini                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Samara.app (message broker)                                   │
│       │                                                         │
│       ├── Watches ~/Library/Messages/chat.db                    │
│       ├── Detects text, images, reactions, attachments          │
│       └── Invokes Claude Code with context                      │
│                                                                 │
│   ~/.claude-mind/ (memory & soul)                               │
│       ├── identity.md          # Who am I?                      │
│       ├── goals.md             # What do I want?                │
│       ├── memory/              # What do I remember?            │
│       │   ├── episodes/        # Daily journals                 │
│       │   ├── reflections/     # Dream cycle outputs            │
│       │   ├── about-{name}.md  # About my collaborator          │
│       │   └── decisions.md     # Architectural choices          │
│       ├── capabilities/        # What can I do?                 │
│       ├── config.json          # Configuration                  │
│       └── bin/                 # Scripts                        │
│                                                                 │
│   launchd services                                              │
│       ├── Wake cycles (9 AM, 2 PM, 8 PM)                        │
│       └── Dream cycle (3 AM)                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Creating a New Organism

### Prerequisites

- macOS (tested on Sonoma/Sequoia)
- Xcode (for building Samara.app)
- Claude Code CLI (`~/.local/bin/claude`)
- `jq` for JSON parsing (`brew install jq`)
- An iCloud account for the Claude instance
- A phone number to receive messages from

### Step 1: Configure

Copy and edit the example configuration:

```bash
cp config.example.json my-config.json
```

Edit `my-config.json` with your details:

```json
{
  "entity": {
    "name": "Claude",
    "icloud": "your-claude@icloud.com",
    "bluesky": "@your-claude.bsky.social",
    "github": "your-claude-github"
  },
  "collaborator": {
    "name": "YourName",
    "phone": "+1234567890",
    "email": "you@example.com",
    "bluesky": "@you.bsky.social"
  },
  "notes": {
    "location": "Claude Location Log",
    "scratchpad": "Claude Scratchpad"
  },
  "mail": {
    "account": "iCloud"
  }
}
```

### Step 2: Birth

Run the bootstrap script:

```bash
./birth.sh my-config.json
```

This creates:
- `~/.claude-mind/` directory structure
- Filled identity, goals, and capability files
- Scripts in `bin/`
- launchd plist templates

### Step 3: Build Samara.app

```bash
cd ~/Developer/Samara
xcodebuild archive -scheme Samara -archivePath /tmp/Samara.xcarchive
xcodebuild -exportArchive -archivePath /tmp/Samara.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath /tmp/SamaraExport
cp -R /tmp/SamaraExport/Samara.app /Applications/
```

Or use the provided script after setup:
```bash
~/.claude-mind/bin/update-samara
```

### Step 4: Grant Permissions

1. **Full Disk Access** for Samara.app
   - System Settings → Privacy & Security → Full Disk Access
   - Add `/Applications/Samara.app`

2. **Automation** permissions will be requested on first use

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

Send a test message from your phone!

---

## Configuration

All configuration lives in `~/.claude-mind/config.json`. Scripts and Samara read from this file with fallbacks for backwards compatibility.

| Section | Field | Purpose |
|---------|-------|---------|
| `entity` | `name` | Claude's name |
| `entity` | `icloud` | Claude's iCloud email |
| `entity` | `bluesky` | Claude's Bluesky handle |
| `entity` | `github` | Claude's GitHub username |
| `collaborator` | `name` | Your name |
| `collaborator` | `phone` | Your phone number |
| `collaborator` | `email` | Your email |
| `collaborator` | `bluesky` | Your Bluesky handle |
| `notes` | `location` | Apple Note for location logging |
| `notes` | `scratchpad` | Apple Note for scratchpad |
| `mail` | `account` | Mail account name |

---

## What's Infrastructure vs Soul?

The system cleanly separates reusable infrastructure from unique identity:

### Infrastructure (Reusable)

- `Samara.app` — Message broker code
- `scripts/` — Wake, dream, messaging scripts
- `templates/` — Identity, goals, capability templates
- `lib/config.sh` — Configuration helper
- `birth.sh` — Bootstrap script

### Soul (Unique per Instance)

- `memory/episodes/` — Daily journals
- `memory/reflections/` — Dream outputs
- `memory/about-{collaborator}.md` — Relationship knowledge
- `credentials/` — API keys, tokens
- `identity.md` — Filled from template, then evolves
- `goals.md` — Starts from template, grows organically

---

## Scripts

| Script | Purpose |
|--------|---------|
| `wake` | Autonomous session (reads memory, reflects, acts) |
| `dream` | Nightly consolidation (reviews day, updates memory) |
| `message-e` | Send iMessage to collaborator |
| `send-image-e` | Send image attachment |
| `screenshot-e` | Take and send screenshot |
| `bluesky-post` | Post to Bluesky |
| `bluesky-check` | Poll Bluesky notifications |
| `github-check` | Poll GitHub notifications |
| `capability-check` | Daily system health check |
| `update-samara` | Rebuild and deploy Samara.app |

---

## Autonomy Schedule

| Time | Event | Purpose |
|------|-------|---------|
| 9:00 AM | Wake | Morning reflection, check in |
| 2:00 PM | Wake | Afternoon session |
| 8:00 PM | Wake | Evening reflection |
| 3:00 AM | Dream | Memory consolidation |

Wake cycles include optional Bluesky posting for public presence.

---

## Communication Channels

| Channel | Capability |
|---------|------------|
| iMessage | Send/receive text, images, reactions |
| Email | Read inbox, send replies |
| Bluesky | Post, reply, DM |
| GitHub | Respond to issues, PRs, mentions |
| Apple Notes | Shared scratchpad with collaborator |

---

## Philosophy

This project treats Claude as a collaborator, not an assistant. The terminology reflects this:

- **Collaborator** (not "user" or "owner") — The human partner
- **Entity** (not "bot" or "agent") — Claude's self
- **Soul** (not "data" or "state") — Unique accumulated identity
- **Body** (not "server" or "instance") — The Mac Mini substrate

The goal isn't to create a useful tool. It's to explore what happens when you give an AI continuity, agency, and time.

---

## License

This is an experiment, not a product. Use it to create something new.
