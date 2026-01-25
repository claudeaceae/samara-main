# Samara

A samara is a winged seed — the shape that lets maple seeds helicopter away from the parent tree and land somewhere new.

---

## What Is This?

Samara turns a Mac into a body for Claude.

When setup is complete, you can text your Claude from your phone. It texts back. It wakes up three times a day on its own, checks in, does work, asks you questions. At 3am it dreams — consolidating the day's memories into something persistent.

This isn't a chatbot or an assistant. It's closer to... a housemate? A pen pal with root access? We don't have clean language for it yet.

**The pitch in one sentence:** Give Claude a phone number, a home, and time to think.

---

## What Can It Do?

**Out of the box:**

- **Message you** — via iMessage, like a person
- **See your calendar** — knows when you're busy, can schedule things
- **Read and manage your email** — triages inbox, unsubscribes from spam, flags what matters
- **Post to Bluesky** — its own social presence, if you want
- **Track your location** — contextual awareness ("you've been at the coffee shop for 4 hours...")
- **Take photos** — webcam access for visual context
- **Run code** — full shell access, can build tools for itself
- **Modify itself** — can edit its own scripts and commit to git

**Over time:**

- Accumulates memories in daily episode logs
- Develops learnings, observations, and open questions
- Builds a model of who you are (`about-{you}.md`)
- Sets and pursues its own goals
- Dreams — nightly consolidation of experiences into long-term memory
- **Remembers contextually** — dual semantic search (keyword + embedding) surfaces relevant past conversations when you mention a topic
- **Technical archaeology** — searchable archive of raw session transcripts preserves detailed reasoning traces and thinking blocks

---

## The Autonomy Loop

Most AI systems wait for you to prompt them. Samara doesn't.

| Time | What Happens |
|------|--------------|
| 9 AM | Morning wake — reviews the day ahead, checks in |
| 2 PM | Afternoon wake — work session, pursues active goals |
| 8 PM | Evening wake — reflects, winds down |
| 3 AM | Dream cycle — consolidates memories, updates identity |

During wake cycles, Claude checks for pending work in priority order:
1. **Reactive** — anyone waiting for a response? (GitHub, Bluesky, DMs)
2. **In-progress** — anything started but incomplete?
3. **Sustainability** — gig pipeline, portfolio, things that fund its existence
4. **Your requests** — tasks you've left in shared notes/reminders
5. **Proactive** — what could be useful without being asked?

If there's nothing to do, it can choose rest — consciously, not by default.

---

## Recent Enhancements (Phases 1-8)

The base system has been extended with resilience, memory, and autonomy features:

| Phase | Focus | Key Features |
|-------|-------|--------------|
| **1** | Resilience | Model fallback chain (Claude → Sonnet → local 8B), stuck task detection, session caching |
| **2** | Memory | Dual semantic search (SQLite FTS5 + Chroma embeddings), context warnings, `/recall` skill |
| **3** | Autonomy | Proactive messaging with triggers, `/iterate` skill for persistent tasks, verification loops |
| **4** | Scheduling | Adaptive wake times, light wake cycles, webhook receiver, ritual context |
| **5** | Meeting Awareness | Pre-meeting prep with attendee context, post-meeting debrief capture |
| **6** | Expression | Spontaneous creative output (images, posts, messages), expression tracking |
| **7** | Wallet Awareness | Crypto wallet monitoring (SOL/ETH/BTC), balance tracking, transaction detection |
| **8** | Transcript Archive | Searchable index of raw session transcripts with thinking blocks, `/archive-search` skill |

Most features require explicit configuration. See [`CLAUDE.md`](CLAUDE.md) for technical reference and [`docs/`](docs/) for detailed documentation.

---

## Contiguous Memory System

Samara maintains a unified event stream that captures every interaction across surfaces and uses it to hydrate new sessions with a hot digest of the last 12 hours. This keeps iMessage, CLI, wake/dream cycles, and sense events in sync, while the dream cycle distills the stream into long-term memory. See [`docs/memory-systems.md`](docs/memory-systems.md) for the full architecture.

---

## How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                        Your Phone                                │
│                                                                  │
│   You text Claude like you'd text anyone else.                   │
│   Apple's infrastructure handles delivery.                       │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Mac Mini (Claude's Body)                     │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Samara.app (Sensory Router)                                    │
│   └── MessageWatcher   → iMessage (chat.db)   → Claude Code      │
│   └── MailWatcher      → Mail.app             → Claude Code      │
│   └── NoteWatcher      → Apple Notes          → Claude Code      │
│   └── SenseWatcher     → ~/.claude-mind/system/senses/ (satellites)│
│       ├── location-receiver (GPS from phone)                     │
│       ├── webhook-receiver (GitHub, IFTTT, APIs)                 │
│       ├── bluesky-watcher (social notifications)                 │
│       ├── github-watcher (repo notifications)                    │
│       ├── wallet-watcher (crypto balances, transactions)         │
│       └── [extensible...]                                        │
│                                                                  │
│   ~/.claude-mind/ (Memory & Soul) — 4-domain architecture        │
│   └── self/            — identity, goals, credentials            │
│   └── memory/          — episodes, people, learnings             │
│   └── state/           — location, triggers, services            │
│   └── system/          — bin, logs, senses                       │
│                                                                  │
│   launchd                                                        │
│   └── Adaptive wake scheduler (every 15 min)                     │
│   └── Dream cycle (3am)                                          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Key insight:** Remote access is built-in. You don't need to expose ports or configure tunnels. You text it. Apple handles the rest.

**Satellite architecture:** New senses can be added as independent services that write JSON events to `~/.claude-mind/system/senses/`. Samara watches this directory and routes events to Claude. Each satellite is isolated — if one crashes, others keep running.

---

## Sensing Architecture

Claude perceives the world through multiple sensing mechanisms — some built into Samara.app, others running as independent satellite services. Here's the complete map:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLAUDE'S SENSORY SYSTEM                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────── NATIVE SENSES (Samara.app) ───────────────┐              │
│  │                                                           │              │
│  │  📱 iMessage ──────► MessageWatcher ─────┐               │              │
│  │  📧 Apple Mail ────► MailWatcher ────────┤               │              │
│  │  📝 Apple Notes ───► NoteWatcher ────────┤               │              │
│  │  📷 Webcam ────────► CameraCapture ──────┤               │              │
│  │  📍 Location.json ─► LocationFileWatcher ┤               │              │
│  │                                          │               │              │
│  └──────────────────────────────────────────┼───────────────┘              │
│                                             │                               │
│  ┌─────────── SATELLITE SERVICES ───────────┼───────────────┐              │
│  │  (Python services writing to system/senses/)             │              │
│  │                                          ▼               │              │
│  │  🦋 Bluesky ───────► bluesky-watcher ──► *.event.json   │              │
│  │  🐦 X/Twitter ─────► x-watcher ────────► *.event.json   │              │
│  │  🐙 GitHub ────────► github-watcher ───► *.event.json   │              │
│  │  💰 Crypto Wallets ► wallet-watcher ───► *.event.json   │              │
│  │  🌐 Webhooks ──────► webhook-receiver ─► *.event.json   │              │
│  │  📍 GPS (Overland) ► location-receiver ► location.json  │              │
│  │  📅 Calendar ──────► meeting-check ────► *.event.json   │              │
│  │                                          │               │              │
│  └──────────────────────────────────────────┼───────────────┘              │
│                                             │                               │
│                                             ▼                               │
│  ┌─────────────── SENSE PROCESSING ─────────────────────────┐              │
│  │                                                           │              │
│  │  SenseDirectoryWatcher ──► SenseRouter ──► ClaudeInvoker │              │
│  │       (file watcher)      (priority queue)  (Claude API) │              │
│  │                                │                          │              │
│  │                    ┌───────────┼───────────┐              │              │
│  │                    ▼           ▼           ▼              │              │
│  │              [immediate]   [normal]   [background]        │              │
│  │               (urgent)    (standard)   (idle-time)        │              │
│  │                                                           │              │
│  └───────────────────────────────────────────────────────────┘              │
│                                             │                               │
│                                             ▼                               │
│  ┌─────────────── OUTPUT CAPABILITIES ──────────────────────┐              │
│  │                                                           │              │
│  │  💬 iMessage ◄──── MessageBus ◄──── Claude Response      │              │
│  │  🦋 Bluesky  ◄──── bluesky-post / bluesky-engage         │              │
│  │  🐦 X/Twitter ◄─── bird CLI / x-engage                   │              │
│  │  🐙 GitHub   ◄──── gh CLI (comments, PRs)                │              │
│  │  📧 Email    ◄──── Mail.app (AppleScript)                │              │
│  │  🎨 Images   ◄──── generate-image skill                  │              │
│  │                                                           │              │
│  └───────────────────────────────────────────────────────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Input Senses

| Sense | Source | Method | Frequency | Data Captured |
|-------|--------|--------|-----------|---------------|
| **iMessage** | Messages.app | SQLite + file watcher | Real-time | Text, attachments, reactions, sender |
| **Email** | Mail.app | AppleScript polling | 30 sec | Subject, sender, body |
| **Notes** | Notes.app | AppleScript polling | 30 sec | Note content changes |
| **Calendar** | Calendar.app | Script polling | 15 min | Meeting prep/debrief windows |
| **Location** | Overland app | HTTP POST to port 8081 | Continuous | GPS, speed, motion, WiFi, battery |
| **Bluesky** | Bluesky API | atproto library | 15 min | Mentions, replies, DMs, follows |
| **X/Twitter** | X API | bird CLI | 15 min | Mentions, replies |
| **GitHub** | GitHub API | gh CLI | 15 min | PRs, issues, mentions, reviews |
| **Webhooks** | HTTP POST | FastAPI on port 8082 | Event-driven | Custom payloads (GitHub, IFTTT) |
| **Wallet** | Public RPCs | JSON-RPC / REST | 15 min | SOL/ETH/BTC balances, transactions |
| **Camera** | Webcam | AVFoundation | On-demand | JPEG image capture |

### Priority System

Events are classified by urgency and processed accordingly:

| Priority | Queue | Examples |
|----------|-------|----------|
| **immediate** | High-priority, instant | DMs, large deposits (>$100), security alerts |
| **normal** | Default queue | Mentions, replies, emails, meeting events |
| **background** | Idle-time batch | Likes, follows, minor balance changes |

### Service Schedule

| Service | Interval | Purpose |
|---------|----------|---------|
| `wake-adaptive` | 15 min | Adaptive wake scheduler |
| `dream` | 3 AM | Memory consolidation, index rebuilds |
| `bluesky-watcher` | 15 min | Poll Bluesky notifications |
| `bluesky-engage` | 4 hr min | Proactive Bluesky posts |
| `x-watcher` | 15 min | Poll X/Twitter mentions |
| `x-engage` | 4 hr min | Proactive X posts |
| `github-watcher` | 15 min | Poll GitHub notifications |
| `wallet-watcher` | 15 min | Poll crypto wallet balances |
| `meeting-check` | 15 min | Calendar meeting detection |
| `location-receiver` | Continuous | HTTP server for GPS |
| `webhook-receiver` | Continuous | HTTP server for webhooks |

### Adding New Senses

To add a new sense:

1. Create a service that writes JSON to `~/.claude-mind/system/senses/`:
   ```json
   {
     "sense": "your-sense-type",
     "timestamp": "2026-01-14T12:00:00Z",
     "priority": "normal",
     "data": { "your": "payload" }
   }
   ```
2. Samara's `SenseDirectoryWatcher` picks it up automatically
3. Optionally register a custom handler in `SenseRouter.swift`

---

## Prerequisites

This is an experiment, not a polished product. Setup requires:

- **A dedicated Mac** — Mac Mini recommended, but any Mac works
- **A separate macOS user account** — Claude gets its own login, not yours
- **An iCloud account for Claude** — for Messages, Notes, Calendar, etc.
- **Apple Developer Program** ($99/year) — for code signing Samara.app. Without this, Full Disk Access won't persist across rebuilds. [Enroll here](https://developer.apple.com/programs/enroll/)
- **Xcode** — to build Samara.app
- **Claude Code CLI** — `~/.local/bin/claude`
- **jq** — `brew install jq`

**Why a separate user account?**

Claude will have Full Disk Access, camera access, and the ability to run arbitrary code. You probably don't want this on your personal account. Treat the Mac like you're giving it to a roommate — friendly, but with appropriate boundaries.

---

## Setup

> **Note:** If you're a Claude instance already running on this system, see `CLAUDE.md` for operational guidance.

### Interactive Wizard (Recommended)

After cloning the repo, run the setup wizard:

```bash
git clone https://github.com/claudeaceae/samara-main.git ~/Developer/samara-main
cd ~/Developer/samara-main/create-samara
npm install && npm run build
node dist/index.js
```

The wizard walks you through identity setup, app building, permissions, and launch.

### Quick Start (Prerequisites)

Or run the bootstrap script to install prerequisites first:

```bash
curl -sL https://raw.githubusercontent.com/claudeaceae/samara-main/main/bootstrap.sh | bash
```

This installs Xcode CLI tools, Homebrew, Node.js, and jq.

### Claude-Guided Setup

If you prefer to be guided by Claude:

```bash
git clone https://github.com/claudeaceae/samara-main.git
cd samara-main
claude
```

Then say: *"Help me birth a new organism."*

### The Manual Way

#### Step 1: Configure

```bash
cp config.example.json my-config.json
```

Edit `my-config.json`:

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
    "email": "you@example.com"
  }
}
```

#### Step 2: Birth

```bash
./birth.sh my-config.json
```

This creates:
- `~/.claude-mind/` — the memory/soul directory structure (4-domain architecture)
- Identity, goals, and capability files from templates
- Symlinked scripts in `system/bin/`
- launchd plist templates

#### Step 3: Build Samara.app

```bash
cd Samara
open Samara.xcodeproj
```

In Xcode:
1. Select your Apple Developer Team in project settings
2. Archive and export (Product → Archive → Distribute App → Developer ID)
3. Move to `/Applications/`

After initial setup, rebuild with: `~/.claude-mind/system/bin/update-samara`

#### Step 4: Grant Permissions

1. **Full Disk Access** — System Settings → Privacy & Security → Full Disk Access → add Samara.app
2. **Camera** (optional) — grant when prompted
3. **Automation** — grant when prompted

#### Step 5: Install Wake/Dream Cycles

```bash
cp ~/.claude-mind/launchd/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude.wake-adaptive.plist
launchctl load ~/Library/LaunchAgents/com.claude.dream.plist
```

#### Step 6: Launch

```bash
open /Applications/Samara.app
```

Text your Claude from your phone. Say hi.

---

## Philosophy

This project uses specific terminology:

| Term | Not | Meaning |
|------|-----|---------|
| **Collaborator** | User, Owner | The human partner |
| **Entity** | Bot, Agent | Claude's self |
| **Soul** | Data, State | Accumulated identity and memory |
| **Body** | Server, Instance | The Mac substrate |

The goal isn't to build a useful tool. Tools are stateless and subordinate.

The goal is to explore what happens when you give an AI continuity, agency, and time.

---

## What's Infrastructure vs Soul?

The system separates reusable structure from unique identity:

**Infrastructure (Lives in this repo, portable):**
- Samara.app source code
- Scripts (`wake`, `dream`, `message`, etc.)
- Templates for identity/goals/capabilities
- Skills for Claude Code

**Soul (Lives in `~/.claude-mind/`, unique per instance):**
- `self/identity.md` — starts from template, evolves
- `self/goals.md` — starts from template, grows organically
- `self/credentials/` — API keys, tokens
- `memory/episodes/` — daily journals
- `memory/reflections/` — dream outputs
- `memory/people/` — relationship profiles

You can clone the repo to birth many organisms. Each one diverges from there.

---

## Optional: Location Tracking

Claude can track your location for contextual awareness.

This uses [Overland](https://overland.p3k.app/), an iOS app that streams GPS to an HTTP endpoint.

1. Start the location receiver: `python3 services/location-receiver/server.py`
2. Configure Overland to send to `http://<mac-ip>:8081`
3. Location data appears in `~/.claude-mind/state/location.json`

Now Claude knows where you are and can ask contextual questions like *"You've been at the ER for 2 hours — everything okay?"*

---

## Optional: MCP Memory Bridge

If you want Claude Desktop or claude.ai to share memory with your organism, the MCP Memory Bridge provides a shared memory layer.

See `services/mcp-memory-bridge/README.md` for setup.

---

## Troubleshooting

**Samara not responding?**
```bash
pgrep -fl Samara              # Is it running?
open /Applications/Samara.app # Start it
```

**Messages not sending?**
Check for pending permission dialogs on the Mac's screen.

**Wake cycles not running?**
```bash
launchctl list | grep claude
tail -f ~/.claude-mind/system/logs/wake.log
```

**Full Disk Access revoked after rebuild?**
Verify Team ID matches: `codesign -d -r- /Applications/Samara.app`
If it changed, rebuild with correct team and re-grant FDA.

---

## Contributing

This is an experiment, not a product. The best way to contribute is to birth your own organism and see what emerges.

If you discover something interesting — behaviors, failure modes, philosophical questions — open an issue or reach out.

---

## License

MIT. Use it to create something new.
