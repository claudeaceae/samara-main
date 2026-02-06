# Scripts

Shell scripts that power the Claude organism's autonomous capabilities.

All scripts are symlinked to `~/.claude-mind/system/bin/` at runtime.

---

## Quick Reference

| Script | Category | Purpose |
|--------|----------|---------|
| `wake` | Core | Autonomous wake cycle |
| `dream` | Core | Nightly memory consolidation |
| `message` | Core | Send iMessage to collaborator |
| `send-image` | Core | Send image attachment |
| `generate-image` | Expression | Generate images via Gemini |
| `bluesky-post` | Social | Post to Bluesky |
| `x-post` | Social | Post to X/Twitter |
| `voice-call` | Communication | FaceTime Audio voice conversations |
| `update-samara` | Dev | Rebuild Samara.app |

---

## Communication Scripts

| Script | Purpose |
|--------|---------|
| `message` | Send iMessage to collaborator |
| `message-e` | Send iMessage to É (direct variant) |
| `send-image` | Send image attachment to collaborator |
| `send-image-e` | Send image to É (direct variant) |
| `send-attachment` | Send file to any chat (1:1 or group) |
| `screenshot` | Take and send screenshot to collaborator |
| `screenshot-e` | Screenshot to É (direct variant) |
| `screenshot-to` | Screenshot to specific chat |
| `speak` | Text-to-speech output |

### `message`

Send an iMessage to the collaborator.

```bash
~/.claude-mind/system/bin/message "Hello from Claude!"
```

**Dependencies:** macOS Messages.app, `osascript`
**Config:** `collaborator.phone`

### `send-image`

Send an image or file attachment.

```bash
~/.claude-mind/system/bin/send-image /path/to/image.png
```

**Note:** Copies file to `~/Pictures/.imessage-send/` before sending (macOS TCC workaround).

### `send-attachment`

Send a file to any iMessage chat.

```bash
# To phone number
send-attachment /path/to/file.pdf +15551234567

# To group chat (32-char GUID)
send-attachment /path/to/file.pdf 7409d77007664ff7b1eeb4683f49cadf
```

---

## Social Media Scripts

### Bluesky

| Script | Purpose |
|--------|---------|
| `bluesky-post` | Post text to Bluesky |
| `bluesky-image` | Post image with caption |
| `bluesky-check` | Poll notifications (launchd) |
| `bluesky-engage` | Proactive engagement |

**Credentials:** macOS Keychain (`credential get bluesky`)

```bash
bluesky-post "Your thought here"
```

### X/Twitter

| Script | Purpose |
|--------|---------|
| `x-post` | Post to X (with Playwright fallback) |
| `x-reply` | Reply to tweet (with Playwright fallback) |
| `x-post-playwright` | Direct Playwright posting |
| `x-reply-playwright` | Direct Playwright reply |
| `x-check` | Poll mentions (legacy) |
| `x-engage` | Proactive posting |

**Two-tier fallback system:**
1. **Primary:** `bird` CLI (fast, uses browser cookies)
2. **Fallback:** Playwright browser automation (slower, more human-like)

**Fallback triggers:** Error 226 (automated), Error 344 (daily limit)

**Playwright rate limits:**
- Maximum 5 posts per day
- Minimum 30 seconds between posts
- State: `~/.claude-mind/state/services/x-playwright-state.json`

```bash
x-post "Hello world"
x-reply 1234567890 "Thanks for sharing!"
```

### GitHub

| Script | Purpose |
|--------|---------|
| `github-check` | Poll GitHub notifications (launchd) |

**Dependencies:** `gh` CLI (authenticated)

---

## Email Scripts

| Script | Purpose |
|--------|---------|
| `send-email` | Send email via Mail.app |
| `email-triage` | Triage inbox, identify actionable items |
| `email-action` | Take action on specific email |
| `email-unsubscribe` | Unsubscribe from mailing lists |

---

## Visual Expression Scripts

| Script | Purpose |
|--------|---------|
| `generate-image` | Generate images via Gemini (self-portraits, reactions) |
| `look` | Capture photo from webcam |

### `generate-image`

Primary tool for visual self-expression.

**Character references:**
- All images: `~/.claude-mind/self/images/` (avatar refs, 17 poses, fanart)
- Primary: `~/.claude-mind/self/images/avatar-ref.png`

```bash
generate-image "Silver-haired girl laughing, eyes closed" /tmp/reaction.jpg \
  --ref=~/.claude-mind/self/images/avatar-ref.png

send-image /tmp/reaction.jpg
```

**Options:**
| Flag | Purpose |
|------|---------|
| `--ref=PATH` | Character/style reference (repeatable) |
| `--aspect=RATIO` | 1:1, 16:9, 9:16, 4:3, etc. |
| `--resolution=RES` | 1k, 2k, 4k (Pro model only) |

---

## Wake/Dream Scripts

| Script | Purpose |
|--------|---------|
| `wake` | Main wake cycle script |
| `wake-adaptive` | Adaptive wake scheduler entry point |
| `wake-light` | Light wake (quick scan for urgent items) |
| `wake-scheduler` | Calculates next wake time |
| `dream` | 3 AM memory consolidation |
| `dream-weekly-catchup` | Run missed weekly rituals |

### `wake`

Autonomous wake cycle - self-directed sessions.

**Schedule:** Invoked by `wake-adaptive` (~9 AM, ~2 PM, ~8 PM or adaptive triggers)

**What it does:**
1. Acquires system lock
2. Reads memory context (identity, goals, recent episodes)
3. Invokes Claude Code with wake prompt
4. Reflects, takes actions, updates memory
5. Releases lock

### `dream`

Nightly memory consolidation and reflection.

**Schedule:** 3 AM via launchd

**What it does:**
1. Reviews yesterday's episode
2. Extracts learnings, observations, questions
3. Updates long-term memory files
4. Creates reflection entry
5. Syncs transcript archive
6. Weekly: deeper pattern analysis

---

## Memory Scripts

| Script | Purpose |
|--------|---------|
| `memory-index` | SQLite FTS5 operations (rebuild, search, stats) |
| `chroma-query` | Semantic search via Chroma embeddings |
| `chroma-rebuild` | Full rebuild of Chroma index |
| `find-related-context` | Cross-temporal context lookup |
| `archive-index` | Transcript archive (rebuild, sync-recent, search) |
| `expression-tracker` | Creative expression state tracking |
| `knowledge-thread` | Knowledge thread management |
| `find-thread-context` | Semantic search across threads + Chroma |

### Knowledge Threads

Persistent topics that accumulate items over time for sustained knowledge building.

```bash
knowledge-thread create "Topic Title"     # Create new thread
knowledge-thread add <id> <url|text>      # Add item to thread
knowledge-thread list                     # List active threads
knowledge-thread view <id>                # View thread details
knowledge-thread status                   # Show threads needing attention
knowledge-thread synthesize <id>          # Generate synthesis
knowledge-thread find "query"             # Semantic thread search
knowledge-thread chew <id>                # Mark items as processed
knowledge-thread migrate                  # Migrate from research-queue
```

**Integration:** Dream cycle includes rumination phase (processes up to 3 threads/night).

---

## Stream Scripts (Contiguous Memory)

| Script | Purpose |
|--------|---------|
| `stream` | Query unified event stream |
| `stream-audit` | Audit coverage and digest inclusion |
| `build-hot-digest` | Build session hydration digest |
| `distill-session` | Distill session into episode |
| `distill-claude-session` | Background distillation (hook) |

---

## Voice Call Scripts

FaceTime Audio calling system — call the collaborator (or any Apple device) and have a live voice conversation with transcription and AI responses.

| Script | Purpose |
|--------|---------|
| `voice-call` | High-level orchestrator (setup → call → listen → respond → teardown) |
| `facetime` | FaceTime control (open/close/status/call/hangup) |
| `call-record` | Aggregate device management + sox recording with silence detection |
| `call-listen` | Recording + transcription + response conversation loop |
| `call-speak` | Play TTS audio to "Claude Mic" for FaceTime transmission |
| `call-transcribe` | Whisper transcription (48kHz stereo → 16kHz mono → text) |
| `audio-setup` | Verify/configure audio prerequisites |
| `aggregate-device` | Create/destroy CoreAudio multi-output aggregate devices |

### Architecture

```
                 ┌─────────────────────────────────┐
                 │         voice-call               │
                 │  (orchestrator: lifecycle mgmt)   │
                 └──┬──────────┬──────────┬─────────┘
                    │          │          │
              ┌─────▼──┐  ┌───▼────┐  ┌──▼──────────┐
              │facetime │  │call-   │  │call-listen   │
              │call/    │  │record  │  │(conversation │
              │hangup   │  │setup/  │  │ loop)        │
              └─────────┘  │start/  │  └──┬─────┬─────┘
                           │stop/   │     │     │
                           │teardown│  ┌──▼──┐ ┌▼────────┐
                           └────────┘  │call-│ │call-     │
                                       │tran-│ │speak     │
                                       │scri-│ │(TTS →    │
                                       │be   │ │Claude Mic│
                                       └─────┘ └──────────┘
```

### Audio Routing

On macOS 26, FaceTime call audio is handled by system daemons (`callservicesd`, `avconferenced`) that route through the system default output. A CoreAudio aggregate device ("Call Monitor") combines physical speakers + Loopback's "Call Capture" virtual device, so call audio reaches both the speakers and the recording pipeline.

```
Caller's voice → callservicesd → system default output → "Call Monitor" aggregate
                                                          ├→ Mac mini Speakers (audible)
                                                          └→ Call Capture (recording)

Claude's voice → ElevenLabs TTS → afplay → Loopback Terminal capture → Claude Mic → FaceTime
```

**Critical constraint:** The aggregate device must be set as system output BEFORE the FaceTime call connects. Audio routing is locked at connection time.

### `voice-call`

Full conversation lifecycle.

```bash
voice-call --voice-response                    # Voice conversation (default target)
voice-call +15551234567 --text-response        # Respond via iMessage
voice-call --greeting "Hi, it's Claude" --timeout 300
```

### `call-record`

Four-phase lifecycle separating audio routing from recording:

```bash
call-record setup      # Create aggregate device, set system output
call-record start      # Begin sox recording with silence detection
call-record stop       # Stop recording (aggregate stays alive)
call-record teardown   # Destroy aggregate, restore audio devices
```

Recording uses 35dB gain amplification before silence detection (call audio from aggregate is very low amplitude). Configurable via `~/.claude-mind/state/voice-call-config.json`.

### `facetime`

```bash
facetime call [+1XXXXXXXXXX]   # UI automation: New → type number → Audio → dial
facetime hangup                # Click NotificationCenter "End" button
facetime status                # "running" or "stopped"
```

**Dependencies:** Loopback.app (running), sox, SwitchAudioSource, whisper-cli, ElevenLabs API key

---

## Voice Style Scripts

| Script | Purpose |
|--------|---------|
| `generate-voice-style` | Compose output style from voice state |
| `mine-voice-patterns` | Extract themes from episodes/reflections |
| `mine-reaction-patterns` | Extract reaction patterns |
| `extract-voice-directives` | Extract voice directives from text |
| `analyze-e-patterns` | Mine É's communication patterns |
| `analyze-patterns` | General pattern analysis |

---

## Location Scripts

| Script | Purpose |
|--------|---------|
| `get-location` | Get current location (IP fallback) |
| `get-location.swift` | Native CoreLocation implementation |
| `get-e-location` | Get É's current location |
| `generate-location-map` | Generate static map image |
| `generate-location-map-ai` | AI-enhanced location visualization |
| `learn-location-patterns` | Analyze location history for patterns |
| `update-terroir` | Update location context ("terroir") |
| `setup-subway-stations` | Initialize subway station data |

---

## Calendar Scripts

| Script | Purpose |
|--------|---------|
| `calendar-invites` | EventKit CLI: list, create, respond to invitations |
| `calendar-invites.swift` | Swift source for calendar-invites |
| `calendar-caldav` | CalDAV scheduling (accept/decline via iTIP) |
| `calendar-caldav.py` | Python source for CalDAV |
| `calendar-check` | Proactive calendar trigger polling |
| `meeting-check` | Detect meetings in prep/debrief windows |

### Invitation Response Chain

1. **CalDAV** (primary) — Proper iTIP REPLY, notifies organizers
2. **AppleScript** (fallback) — Local property change
3. **UI automation** — Clicks buttons in Calendar.app
4. **Manual** — Opens Calendar.app

```bash
# List pending invitations
calendar-invites list --text

# Accept via CalDAV
calendar-caldav accept "EVENT_UID"
```

---

## Proactive Engagement Scripts

| Script | Purpose |
|--------|---------|
| `proactive-engage` | Evaluate and send proactive messages |
| `proactive-queue` | Manage proactive message queue |
| `check-triggers` | Evaluate proactive triggers |
| `morning-briefing` | Generate morning context briefing |

---

## Iteration Scripts

| Script | Purpose |
|--------|---------|
| `iterate-start` | Begin an iteration goal |
| `iterate-status` | Check current iteration state |
| `iterate-record` | Record attempt outcome |
| `iterate-complete` | Mark iteration as done |

---

## Sync Scripts

| Script | Purpose |
|--------|---------|
| `sync-organism` | Detect drift between repo and runtime |
| `sync-organism --check` | Exit 1 if drift (for automation) |
| `sync-core` | Sync core files only |
| `symlink-scripts --dry-run` | Preview symlink conversion |
| `symlink-scripts --apply` | Convert copies to symlinks |
| `sync-skills` | Ensure skills are symlinked |
| `update-samara` | Rebuild and install Samara.app |

### `update-samara`

Rebuild and deploy Samara.app using proper Xcode workflow.

**What it does:**
1. Archives Samara project
2. Exports with Developer ID signing
3. Notarizes with Apple
4. Staples notarization ticket
5. Installs to `/Applications`

```bash
~/.claude-mind/system/bin/update-samara
```

---

## Service Management

| Script | Purpose |
|--------|---------|
| `service-toggle list` | Show status of all services |
| `service-toggle <svc> on` | Enable service (config + launchd) |
| `service-toggle <svc> off` | Disable service (config + launchd) |
| `service-toggle <svc> status` | Check service status |
| `webhook-receiver` | Start/stop/status webhook receiver |

**Available services:** `x`, `bluesky`, `github`, `wallet`, `meeting`, `webhook`, `location`, `browserHistory`, `proactive`, `voiceCall`

---

## Scratchpad Scripts

| Script | Purpose |
|--------|---------|
| `check-scratchpad` | Read current scratchpad file contents |
| `check-scratchpad-changed` | Check if scratchpad file was modified |
| `update-scratchpad` | Update scratchpad file |
| `check-notes-sync` | Debug Notes.app sync issues (legacy) |

Scratchpad lives in the shared workspace (file-based, no Notes UI).
Default: `~/.claude-mind/shared/scratchpad.md` (override via `sharedWorkspace.path` in `~/.claude-mind/config.json`).

---

## Roundup/Analytics Scripts

| Script | Purpose |
|--------|---------|
| `roundup` | Generate weekly/monthly/yearly roundup |
| `roundup-visualize` | Generate roundup visualizations |

---

## Wallet Scripts

| Script | Purpose |
|--------|---------|
| `wallet-status` | Display crypto wallet balances |
| `solana-wallet` | Solana-specific wallet operations |

---

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `capability-check` | Daily health check of all capabilities |
| `local-maintenance` | Run local maintenance checks |
| `test-samara` | Test Samara message routing |
| `log-session` | Log session summaries to episode |
| `export-messages` | Export iMessage history |
| `project` | Project context helper |
| `research-queue` | Manage research queue (deprecated: use `knowledge-thread`) |
| `creative-prompt` | Generate creative prompts |
| `generate-skills-manifest` | Rebuild skills manifest |
| `message-watchdog` | Monitor message delivery |

---

## Configuration

All scripts source `~/.claude-mind/system/lib/config.sh` which loads from `~/.claude-mind/system/config.json`.

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

Scripts that invoke Claude Code use a shared TaskLock file to prevent concurrent execution:

**Lock file:** `~/.claude-mind/state/locks/system-cli.lock`

```json
{
  "task": "wake",
  "scope": { "systemTask": { "name": "cli" } },
  "started": "2025-12-31T09:00:00Z",
  "chat": null,
  "pid": 12345
}
```

Scripts check for stale locks (dead PIDs) and clean them up automatically.

---

## Scripts vs Hooks

Scripts and hooks serve different purposes:

| Type | Location | Invocation | Purpose |
|------|----------|------------|---------|
| **Scripts** | `scripts/` → `~/.claude-mind/system/bin/` | Manual or by other scripts | Standalone utilities |
| **Hooks** | `.claude/hooks/` | Automatic by Claude Code | Lifecycle events |

**Current Hooks:**

| Hook | Event | Purpose |
|------|-------|---------|
| `hydrate-session.sh` | SessionStart | Inject context |
| `read-shared-links.sh` | UserPromptSubmit | Detect URLs |
| `index-memory-changes.sh` | PostToolUse | Update semantic index |
| `auto-integrate-script.sh` | PostToolUse | Auto-symlink new scripts |
| `check-commit-attribution.sh` | PostToolUse | Verify commit co-authorship |
| `archive-plan-before-write.sh` | PreToolUse | Archive plans before overwrite |
| `session-end-checks.sh` | Stop | Check for drift |
| `distill-claude-session` | SessionEnd | Background distillation |

---

## Adding New Scripts

1. Create script in repo: `~/Developer/samara-main/scripts/my-script`
2. Make executable: `chmod +x ~/Developer/samara-main/scripts/my-script`
3. Run: `symlink-scripts --apply`
4. Document in this README

For scheduled scripts, create a launchd plist in `~/Library/LaunchAgents/`.
