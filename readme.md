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

> **Note:** If you're a Claude instance already running on this system, see `CLAUDE.md` for operational guidance. This readme is for humans setting up new organisms.

### The Easy Way

If you have Claude Code installed:

```bash
git clone https://github.com/claudeaceae/samara-main.git
cd samara-main
claude
```

Then say: "Help me birth a new organism."

Claude will guide you through configuration, run birth.sh, and help with the remaining setup steps.

### Prerequisites

- macOS (tested on Sonoma/Sequoia)
- Xcode (for building Samara.app)
- **Apple Developer Program** ($99/year) — Required for proper code signing. Without this, Full Disk Access won't persist across rebuilds of Samara.app. [Enroll here](https://developer.apple.com/programs/enroll/)
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

The Samara Xcode project is included in this repo at `Samara/`:

```bash
cd Samara

# First time: Open in Xcode to set up signing
open Samara.xcodeproj
# 1. Select your Apple Developer Team in project settings
# 2. Update the Team ID in ExportOptions.plist
# 3. Archive and export (Product → Archive)

# Or use command line after Xcode is configured:
xcodebuild -scheme Samara -configuration Release archive -archivePath /tmp/Samara.xcarchive
xcodebuild -exportArchive -archivePath /tmp/Samara.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath /tmp/SamaraExport
cp -R /tmp/SamaraExport/Samara.app /Applications/
```

After initial setup, use the provided script:
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
| `message` | Send iMessage to collaborator |
| `send-image` | Send image attachment |
| `screenshot` | Take and send screenshot |
| `bluesky-post` | Post to Bluesky |
| `bluesky-check` | Poll Bluesky notifications |
| `github-check` | Poll GitHub notifications |
| `capability-check` | Daily system health check |
| `update-samara` | Rebuild and deploy Samara.app |

---

## Skills

Claude Code skills are interactive slash commands that provide structured workflows for common operations. Skills are installed to `~/.claude/skills/` during birth (symlinked from this repo).

After installation, restart Claude Code to load the skills. They can be invoked explicitly (`/status`) or triggered naturally through conversation.

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/status` | "check status", "is it running" | System health check - Samara, wake cycles, FDA, disk space |
| `/reflect` | "I noticed...", "just realized" | Quick capture of learnings, observations, or insights |
| `/memory` | "what did I learn about", "remember when" | Search through all memory files |
| `/morning` | "morning briefing", "what's on deck" | Daily overview - calendar, location, context |
| `/samara` | "messages not working", "restart samara" | Debug/restart Samara, view logs, check FDA |
| `/episode` | "what happened today", "add to log" | View or append to today's episode |
| `/location` | "where am I", "location context" | Current location with patterns and nearby places |
| `/decide` | "let's document this decision" | Capture decisions with rationale and alternatives |
| `/capability` | "can I do X", "what's possible" | Check if specific actions are available |

### Skill Architecture

Skills live in `.claude/skills/` in this repo. Each skill is a directory containing a `SKILL.md` file with:

```yaml
---
name: skill-name
description: When to trigger this skill (keywords, phrases)
---

# Skill Title

Instructions for Claude to follow when the skill is invoked...
```

The `birth.sh` script symlinks these to `~/.claude/skills/` so they're available globally.

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

## Location Tracking (Optional)

Claude can track your location for proactive awareness (e.g., "You've been at the coffee shop for 4 hours—everything okay?").

This uses [Overland](https://overland.p3k.app/), an iOS app that streams GPS data to an HTTP endpoint.

### Setup

1. **Start the location receiver** (see `services/location-receiver/`):
   ```bash
   # Run directly
   python3 services/location-receiver/server.py

   # Or install as launchd service
   cp services/location-receiver/co.organelle.location-receiver.plist ~/Library/LaunchAgents/
   # Edit the plist to fix paths, then:
   launchctl load ~/Library/LaunchAgents/co.organelle.location-receiver.plist
   ```

2. **Configure Overland** on your phone:
   - Set receiver URL to `http://<mac-ip>:8081`
   - Enable background tracking

3. **Network**: Your Mac must be reachable from your phone (same WiFi, or use Tailscale)

Location data is stored in `~/.claude-mind/state/location.json`.

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
