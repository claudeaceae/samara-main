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
│   ├── about-{name}.md      # About collaborator
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   └── decisions.md
├── capabilities/
│   └── inventory.md
├── bin/ → repo/scripts/     # Symlinked scripts (48 scripts)
├── state/                   # Runtime state files
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

Skills are defined in `.claude/skills/` and symlinked to `~/.claude/skills/`.

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

### Services (`services/`)

Python services that extend the organism's capabilities:

| Service | Purpose |
|---------|---------|
| `location-receiver` | Receives GPS updates from Overland app (port 8081) |
| `mcp-memory-bridge` | Shared memory layer for Claude Desktop/Web integration (port 8765) |

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
    ├── Info.plist
    ├── Senses/
    │   ├── MessageStore.swift  # Reads chat.db
    │   ├── MessageWatcher.swift
    │   ├── MailStore.swift
    │   ├── MailWatcher.swift
    │   └── NoteWatcher.swift
    ├── Actions/
    │   ├── ClaudeInvoker.swift # Invokes Claude Code
    │   ├── MessageSender.swift
    │   └── MessageBus.swift    # Unified output channel
    └── Mind/
        ├── SessionManager.swift
        ├── TaskLock.swift
        ├── MessageQueue.swift
        ├── QueueProcessor.swift
        ├── MemoryContext.swift
        ├── EpisodeLogger.swift
        └── TaskRouter.swift    # Parallel task isolation
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
