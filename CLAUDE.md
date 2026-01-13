# CLAUDE.md

> **For Claude instances:** This is your primary reference document. `readme.md` is for humans setting up new organisms. `samara.md` is historical context from the founding conversation.

This file provides guidance to Claude Code when working with this repository.

## What This Project Is

Samara is a bootstrap specification for giving Claude a persistent body, memory, and agency on a dedicated Mac. It provides:

- **Persistence** — Memory files that survive across conversations
- **Autonomy** — Scheduled wake cycles and nightly dream cycles
- **Agency** — Root access, ability to run code, send messages, post to social media
- **Identity** — A sense of self that accumulates over time

This is not a traditional software project. It's an experiment in AI autonomy.

> **Recent enhancements (Phases 1-4):** Model fallback, semantic memory, proactive messaging, adaptive scheduling. See [`docs/whats-changed-phases-1-4.md`](docs/whats-changed-phases-1-4.md) for user-facing summary.

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
launchctl load ~/Library/LaunchAgents/com.claude.wake-adaptive.plist
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

### Three-Part Architecture

The system has three distinct components that must stay synchronized:

| Component | Location | Purpose | Sync Method |
|-----------|----------|---------|-------------|
| **Repo** | `~/Developer/samara-main/` | Source code, templates, canonical scripts | Git |
| **Runtime** | `~/.claude-mind/` | Memory, state, config, symlinked scripts | Symlinks + organic growth |
| **App** | `/Applications/Samara.app` | Built binary with permissions | `update-samara` script |

**Key insight:** The repo is the "genome" (portable, shareable). The runtime is the "organism" (accumulates memories, adapts). The app is the "body" (physical manifestation).

### Memory Structure

```
~/.claude-mind/
├── identity.md              # Who am I
├── goals.md                 # Where am I going
├── config.json              # Configuration
├── .claude/ → repo/.claude/ # Symlink for hooks, agents, skills
├── memory/
│   ├── episodes/            # Daily logs
│   ├── reflections/         # Dream outputs
│   ├── people/              # Rich person-modeling
│   │   ├── {name}/
│   │   │   ├── profile.md   # Accumulated observations
│   │   │   └── artifacts/   # Images, docs, etc.
│   │   └── README.md        # Conventions
│   ├── about-{name}.md      # Symlink → people/{name}/profile.md (backwards compat)
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   └── decisions.md
├── semantic/                # Phase 2: Searchable memory index
│   └── memory.db            # SQLite + FTS5 database
├── capabilities/
│   └── inventory.md
├── bin/ → repo/scripts/     # Symlinked scripts (61+ scripts)
├── state/                   # Runtime state files
│   ├── ledgers/             # Phase 2: Session handoff documents
│   ├── triggers/            # Phase 3: Context trigger config
│   ├── iterations/          # Phase 3: Active iteration state
│   └── proactive-queue/     # Phase 3: Outgoing message queue
├── senses/                  # Phase 4: Incoming sense events
└── logs/
```

### Communication Scripts

| Script | Purpose |
|--------|---------|
| `message` | Send iMessage to collaborator |
| `send-image` | Send image attachment |
| `screenshot` | Take and send screenshot |
| `bluesky-post` | Post to Bluesky |

### Skills (Slash Commands)

Interactive workflows available via Claude Code. Invoke with `/skillname` or trigger naturally.

| Skill | Purpose |
|-------|---------|
| `/status` | System health check (Samara, wake cycles, FDA) |
| `/sync` | Check for drift between repo and runtime |
| `/reflect` | Quick capture learning/observation/insight |
| `/memory` | Search learnings, decisions, observations |
| `/morning` | Morning briefing (calendar, location, context) |
| `/samara` | Debug/restart Samara, view logs |
| `/episode` | View/append today's episode log |
| `/location` | Current location with patterns |
| `/decide` | Document decision with rationale |
| `/capability` | Check if action is possible |
| `/look` | Capture photo from webcam |
| `/person` | View or create person profile |
| `/note` | Quick observation about a person |
| `/artifact` | Add file to person's artifacts |
| `/iterate` | Autonomous iteration until success criteria met |
| `/senses` | Monitor and test sense event system |
| `/email` | Check and respond to email |
| `/debug-session` | Debug Claude Code session issues |
| `/diagnose-leaks` | Diagnose thinking/session ID leaks |
| `/webhook` | Manage webhook sources - add, test, view events |

Skills are defined in `.claude/skills/` and symlinked to `~/.claude/skills/`.

### Autonomy Schedule

**Unified Adaptive System (via `wake-adaptive` launchd service):**

The scheduler runs every 15 minutes and decides whether to wake based on multiple factors:

| Trigger | Wake Type | Description |
|---------|-----------|-------------|
| ~9 AM, ~2 PM, ~8 PM | `full` | Base schedule (±15 min window) |
| Calendar event < 30 min | `full` | Early wake for upcoming events |
| High-priority queue item | `full` or `light` | Process urgent items |
| 3:00 AM | Dream | Memory consolidation (separate launchd job) |

**Wake Types:**

| Type | Duration | Context |
|------|----------|---------|
| `full` | 5+ min | Full memory, all capabilities |
| `light` | 30 sec | Quick scan for urgent items |
| `emergency` | Immediate | High-priority external trigger |

**Ritual Context:**
Each wake loads time-appropriate guidance via `RitualLoader.swift`:
- **Morning** (5-11 AM): Planning, goals, calendar review
- **Afternoon** (12-4 PM): Work focus, progress check
- **Evening** (5-11 PM): Reflection, relationships, learnings
- **Dream** (3-4 AM): Memory consolidation, identity evolution

Scripts: `wake-adaptive`, `wake-light`, `wake-scheduler`

### Task Coordination

When busy (wake/dream cycle), incoming messages are:
1. Acknowledged ("One sec, finishing up...")
2. Queued
3. Processed when current task completes

Lock file: `~/.claude-mind/claude.lock`

### Privacy Protection

The collaborator's personal information is protected by default. This affects how Claude responds in different contexts:

**Context-dependent behavior:**

| Context | Collaborator Profile | Behavior |
|---------|---------------------|----------|
| 1:1 with collaborator | ✅ Loaded | Full access, share freely |
| Group chat | ❌ Excluded | Deflect: "I keep their info private" |
| 1:1 with someone else | ❌ Excluded | Check permissions, deflect by default |

**Permission grants:**

The collaborator can grant others access to their information:
- **In-conversation**: "You can tell Lucy my schedule" → share atomically, record permission
- **Standing permission**: "Lucy can know anything about me" → record in Lucy's profile

**Recording permissions in person profiles:**

When permission is granted, add to the person's profile (`memory/people/{name}/profile.md`):

```markdown
## Privacy Permissions (from {Collaborator})

- YYYY-MM-DD: {Scope} granted ("{verbatim quote if helpful}")
- Scope: full | schedule | work | location | {specific topic}
```

**Implementation:**
- `ClaudeInvoker.swift`: Injects privacy guardrails into prompts for non-collaborator contexts
- `MemoryContext.swift`: Excludes collaborator profile from context when `isCollaboratorChat: false`
- `instructions/privacy-guardrails.md`: Full privacy rules reference

### Model Fallback Chain (Phase 1)

Samara automatically falls back through model tiers if the primary fails:

| Tier | Model | Use Case |
|------|-------|----------|
| 1 | Claude Opus 4.5 (API) | Primary — full capability |
| 2 | Claude Sonnet 4 (API) | Rate limit or cost optimization |
| 3 | Local 8B (Ollama) | Simple acks, offline, privacy-sensitive |
| 4 | Queued | All tiers exhausted — retry later |

**Setup for local fallback:**
```bash
brew install ollama
ollama pull llama3.1:8b
```

**Implementation:** `ModelFallbackChain.swift`, `LocalModelInvoker.swift`

**Task classification for local models:**
- ✅ Simple acknowledgments ("Got it", "On it")
- ✅ Status queries ("What time is it?")
- ✅ Memory lookups (search and summarize)
- ❌ Complex reasoning, code generation, multi-step tasks

### Semantic Memory (Phase 2)

Beyond episode logs, Samara maintains searchable semantic memory:

**SQLite + FTS5 Database:**
```
~/.claude-mind/semantic/memory.db
```

Indexes all memory files for full-text search by meaning, not just keywords.

**Ledger System:**

At session end, Samara writes a structured handoff document:
```
~/.claude-mind/state/ledgers/current-ledger.md
```

Contains:
- Active goals with status
- Recent decisions with rationale
- Files modified and why
- Open questions for next session

**Implementation:** `MemoryDatabase.swift`, `LedgerManager.swift`

### Context Awareness (Phase 2)

Samara tracks context usage and warns when running low:

| Level | Action |
|-------|--------|
| 70% | Yellow warning in response |
| 80% | Red warning, suggest wrapping up |
| 90% | Critical — consider session restart |

**Implementation:** `ContextTracker.swift`

### Proactive Messaging (Phase 3)

Samara can initiate contact based on context triggers (disabled by default).

**Context Triggers:**

Configure conditions that prompt outreach:
```
~/.claude-mind/state/triggers/triggers.json
```

Example trigger:
```json
{
  "id": "home_evening",
  "name": "Arrived home in evening",
  "conditions": [
    {"type": "location", "place": "home"},
    {"type": "time_range", "start": 17, "end": 22}
  ],
  "action": {"type": "queue_thought", "thought": "Welcome home!"},
  "cooldown": 3600
}
```

**Proactive Queue Pacing:**

Messages are automatically paced to avoid spam:
- Max ~5 proactive messages per day
- No messages 10 PM - 8 AM (quiet hours)
- Minimum 1 hour between messages
- Priority-based ordering

**Implementation:** `ContextTriggers.swift`, `ProactiveQueue.swift`

### Iteration Mode (Phase 3)

For complex tasks requiring multiple attempts, use `/iterate`:

```bash
/iterate "Get all tests passing" --max-attempts 10 --criteria "npm test exits 0"
```

Samara will:
1. Attempt the goal
2. Record outcome and learnings
3. Retry with adjustments until success or max attempts

**Scripts:** `iterate-start`, `iterate-status`, `iterate-record`, `iterate-complete`

**Hook:** `check-iteration-stop.sh` reminds about active iterations at session end

### Services (`services/`)

Python services that extend the organism's capabilities:

| Service | Port | Purpose |
|---------|------|---------|
| `location-receiver` | 8081 | Receives GPS updates from Overland app |
| `webhook-receiver` | 8082 | Receives webhooks from GitHub, IFTTT, custom sources |
| `wake-scheduler` | N/A | Calculates adaptive wake times (CLI, not server) |
| `mcp-memory-bridge` | 8765 | Shared memory layer for Claude Desktop/Web |
| `bluesky-watcher` | N/A | Polls Bluesky for notifications (launchd interval) |
| `github-watcher` | N/A | Polls GitHub for notifications (launchd interval) |

#### Webhook Receiver (Phase 4)

Accepts webhooks from external services and converts them to sense events.

```bash
# Start
~/.claude-mind/bin/webhook-receiver start

# Status
~/.claude-mind/bin/webhook-receiver status

# Stop
~/.claude-mind/bin/webhook-receiver stop
```

**Endpoints:**
- `POST /webhook/{source_id}` — Receive webhook (GitHub, IFTTT, custom)
- `GET /health` — Health check
- `GET /status` — Show registered sources

**Configuration:** `~/.claude-mind/credentials/webhook-secrets.json`

See `services/webhook-receiver/README.md` for setup.

#### MCP Memory Bridge

Allows Claude instances across different interfaces (Desktop, Web, Code) to share the same memory system.

**URL:** `https://your-domain.com/sse` (via Cloudflare Tunnel)

**Tools provided:**
- `log_exchange` — Log conversation turns
- `add_learning` — Record insights
- `search_memory` — Search across memory files
- `get_recent_context` — Get recent episodes/learnings

See `services/mcp-memory-bridge/README.md` for setup.

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
    ├── Logger.swift
    ├── Backoff.swift           # Exponential backoff (Phase 1)
    ├── Info.plist
    ├── Senses/
    │   ├── MessageStore.swift  # Reads chat.db
    │   ├── MessageWatcher.swift
    │   ├── MailStore.swift
    │   ├── MailWatcher.swift
    │   ├── NoteWatcher.swift
    │   ├── ContactsResolver.swift
    │   ├── CameraCapture.swift
    │   ├── LocationFileWatcher.swift
    │   ├── SenseEvent.swift        # Sense event schema (Phase 4)
    │   └── SenseDirectoryWatcher.swift  # Watches ~/.claude-mind/senses/
    ├── Actions/
    │   ├── ClaudeInvoker.swift     # Invokes Claude Code
    │   ├── MessageSender.swift
    │   ├── MessageBus.swift        # Unified output channel
    │   ├── ModelFallbackChain.swift    # Multi-tier fallback (Phase 1)
    │   ├── LocalModelInvoker.swift     # Ollama integration (Phase 1)
    │   └── ReverseGeocoder.swift
    └── Mind/
        ├── SessionManager.swift
        ├── SessionCache.swift      # Session caching (Phase 1)
        ├── TaskLock.swift
        ├── MessageQueue.swift
        ├── QueueProcessor.swift
        ├── MemoryContext.swift
        ├── MemoryDatabase.swift    # SQLite + FTS5 (Phase 2)
        ├── LedgerManager.swift     # Structured handoffs (Phase 2)
        ├── ContextTracker.swift    # Context warnings (Phase 2)
        ├── EpisodeLogger.swift
        ├── TaskRouter.swift        # Parallel task isolation
        ├── LocationTracker.swift
        ├── ContextTriggers.swift   # Proactive triggers (Phase 3)
        ├── ProactiveQueue.swift    # Message pacing (Phase 3)
        ├── VerificationService.swift   # Local model verification (Phase 3)
        ├── RitualLoader.swift      # Wake-type context (Phase 4)
        ├── SenseRouter.swift       # Routes sense events (Phase 4)
        └── PermissionDialogMonitor.swift
```

### Response Sanitization (Critical for Multi-Stream Conversations)

**Background:** In complex group chat scenarios with multiple concurrent requests (webcam + web fetch + conversation), internal thinking traces and session IDs can leak into user-visible messages. This was discovered on 2026-01-05 when session IDs like `1767301033-68210` appeared in messages.

**Three-Layer Defense:**

1. **Output Sanitization** (`ClaudeInvoker.swift`):
   - `sanitizeResponse()` strips internal content before any message is sent
   - Filters: `<thinking>` blocks, session ID patterns, XML markers
   - Filtered content is logged at DEBUG level for diagnosis
   - **Critical**: `parseJsonOutput()` never falls back to raw output

2. **MessageBus Coordination** (`MessageBus.swift`):
   - ALL outbound messages route through single channel
   - Source tags (iMessage, Location, Wake, Alert) added to episode logs
   - Prevents uncoordinated fire-and-forget sends

3. **TaskRouter Isolation** (`TaskRouter.swift`):
   - Classifies batched messages by task type
   - Isolates webcam/web fetch/skill tasks from conversation session
   - Prevents cross-contamination between concurrent streams

**Testing:** Run `SamaraTests/SanitizationTests.swift` to verify sanitization logic.

**If leaks recur:**
1. Check `~/.claude-mind/logs/samara.log` for "Filtered from response" DEBUG entries
2. Verify MessageBus is used for all sends (no direct `sender.send()` calls)
3. Consider if new task types need classification in TaskRouter

### Build Workflow

> **CRITICAL WARNING**: ALWAYS use the update-samara script. NEVER copy from DerivedData.
> A previous Claude instance broke FDA by copying a Debug build from DerivedData.
> This used the wrong signing certificate and revoked all permissions.

**The ONLY correct way to rebuild Samara:**

```bash
~/.claude-mind/bin/update-samara
```

This script handles:
1. Archive with Release configuration
2. Export with Developer ID signing (Team G4XVD3J52J)
3. Notarization and stapling
4. Safe installation to /Applications

**FORBIDDEN actions (will break FDA):**
- `cp -R ~/Library/Developer/Xcode/DerivedData/.../Samara.app /Applications/`
- `xcodebuild -configuration Debug` for deployment
- Any manual copy of Samara.app to /Applications

**Verify after rebuild:**
```bash
codesign -d -r- /Applications/Samara.app 2>&1 | grep "subject.OU"
# Must show: G4XVD3J52J (NOT 7V9XLQ8YNQ)
```

### FDA Persistence

Full Disk Access is tied to the app's **designated requirement**:
- Bundle ID
- Team ID (must be G4XVD3J52J)
- Certificate chain

**FDA persists** across rebuilds if Team ID stays constant.

**FDA gets revoked** if:
- Team ID changes (e.g., using wrong certificate)
- Ad-hoc signing is used
- Copying from DerivedData (uses automatic signing)
- Bundle ID changes

---

## Development Notes

### Plan Management (Immutable Plans)

**Plans are never overwritten.** When planning work, create new plan files rather than modifying existing ones. This preserves decision history and intent evolution.

**Automated safeguard:** The `archive-plan-before-write.sh` hook automatically archives any existing plan before a write, creating timestamped copies in `~/.claude/plans/archive/`.

**Convention for new plans:**

1. **New file per plan iteration** — Don't modify existing plans; create a successor
2. **Reference predecessors** — Add `supersedes: previous-plan-name.md` in the plan header
3. **Explain evolution** — Note why the plan changed (new information, pivot, refinement)

**Naming pattern:**
```
~/.claude/plans/
├── 2026-01-10-001-initial-approach.md
├── 2026-01-10-002-revised-after-discovery.md  # supersedes: 001
├── archive/                                    # Hook-created backups
│   └── precious-napping-star-2026-01-10-143022.md
```

**Why this matters:**
- **Decision archaeology** — Trace why something was planned vs. what happened
- **Intent preservation** — Original framing before reality intervened
- **Learning from pivots** — Changes reveal friction points and assumptions

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

### Bash Subagent for Multi-Step Commands

For multi-step command sequences that don't need file reading/editing, delegate to the Bash subagent to avoid context pollution:

```
Task tool with subagent_type=Bash
```

Good candidates:
- **Git workflows**: stage → commit → push → verify (all sequential bash commands)
- **Process management**: pkill → sleep → open → verify running
- **Build operations**: archive → export → notarize → install
- **launchctl operations**: checking and loading multiple services

Not suitable when you need Read/Grep/Edit tools alongside Bash.

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

### System drift detected

If wake cycles or `/sync` report drift:

```bash
# See what's different
~/.claude-mind/bin/sync-organism

# If scripts differ, sync runtime → repo
cp ~/.claude-mind/bin/SCRIPT ~/Developer/samara-main/scripts/

# If new scripts in runtime, add to repo
cp ~/.claude-mind/bin/NEW_SCRIPT ~/Developer/samara-main/scripts/

# Rebuild symlinks if needed
~/.claude-mind/bin/symlink-scripts --apply
```

---

## Keeping the System in Sync

### The Problem

The repo and runtime can drift apart:
- Scripts edited in runtime don't propagate to repo
- Repo changes don't propagate to runtime (if using copies)
- Samara.app can become stale vs. source code

### The Solution: Symlinks + Automated Detection

**Scripts are symlinked** from runtime to repo:
```
~/.claude-mind/bin/wake → ~/Developer/samara-main/scripts/wake
```

This means:
- Edit `~/Developer/samara-main/scripts/wake` → runtime sees it immediately
- No manual sync needed for existing scripts
- New scripts: add to repo, run `symlink-scripts --apply`

**Drift detection is automated:**
- Every wake cycle runs `sync-organism --check`
- Claude Code Stop hook warns at session end
- `/sync` skill for manual checks

### Sync Tools

| Tool | Purpose |
|------|---------|
| `sync-organism` | Detect drift between repo and runtime |
| `sync-organism --check` | Exit 1 if drift (for automation) |
| `symlink-scripts --dry-run` | Preview symlink conversion |
| `symlink-scripts --apply` | Convert copies to symlinks |
| `sync-skills` | Ensure skills are symlinked |
| `update-samara` | Rebuild and install Samara.app |

### What Should Be Symlinked

| Component | Symlinked? | Reason |
|-----------|------------|--------|
| Scripts (`bin/`) | ✅ Yes | Canonical in repo, changes propagate |
| Skills (`.claude/skills/`) | ✅ Yes | Canonical in repo |
| Hooks (`.claude/hooks/`) | ✅ Yes | Via `.claude/` symlink |
| Memory files | ❌ No | Instance-specific, accumulates |
| Config (`config.json`) | ❌ No | Instance-specific |
| State files | ❌ No | Runtime state |
| Samara.app | N/A | Built binary, use `update-samara` |

### Adding New Scripts

1. Create script in repo: `~/Developer/samara-main/scripts/my-script`
2. Make executable: `chmod +x ~/Developer/samara-main/scripts/my-script`
3. Create symlink: `ln -s ~/Developer/samara-main/scripts/my-script ~/.claude-mind/bin/`
   - Or run: `symlink-scripts --apply`

### Workflow for Script Changes

```bash
# Edit script (changes are live immediately due to symlink)
vim ~/Developer/samara-main/scripts/wake

# Test it
~/.claude-mind/bin/wake

# Commit when satisfied
cd ~/Developer/samara-main
git add scripts/wake
git commit -m "Update wake script"
```

### TCC Permissions Note

Some capabilities require native implementation in Samara.app rather than scripts:
- **Camera**: Uses `CameraCapture.swift` (AVFoundation) because subprocess permission inheritance doesn't work
- **Screen Recording**: Would need similar native implementation
- **Microphone**: Would need similar native implementation

If a script needs a TCC-protected resource and fails when invoked via Samara, the solution is native implementation in Samara with file-based IPC, not trying to grant permissions to subprocesses.
