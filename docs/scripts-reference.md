# Scripts Reference

Catalog of Samara scripts organized by function.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Communication Scripts

| Script | Purpose |
|--------|---------|
| `message` | Send iMessage to collaborator |
| `send-image` | Send image attachment |
| `screenshot` | Take and send screenshot |
| `bluesky-post` | Post text to Bluesky (no flags) |
| `bluesky-image` | Post image to Bluesky with caption |
| `x-post` | Post to X/Twitter (with Playwright fallback) |
| `x-reply` | Reply to X tweet (with Playwright fallback) |
| `x-post-playwright` | Direct Playwright posting (fallback) |
| `x-reply-playwright` | Direct Playwright reply (fallback) |

---

## X/Twitter Fallback System

X posting uses a two-tier fallback system:

1. **Primary**: `bird` CLI (fast, uses browser cookies)
2. **Fallback**: Playwright browser automation (slower, more human-like)

### Fallback Triggers

Fallback triggers when bird fails with:
- Error 226: "This request looks like it might be automated"
- Error 344: "You have reached your daily limit"

### Playwright Rate Limits

To avoid triggering X's anti-automation:
- Maximum 5 Playwright posts per day
- Minimum 30 seconds between Playwright posts
- State tracked in: `~/.claude-mind/state/x-playwright-state.json`

### Usage

```bash
# These automatically fall back to Playwright if bird fails
x-post "Hello world"
x-reply 1234567890 "Thanks for sharing!"

# Direct Playwright (skip bird, useful for testing)
x-post-playwright "Test post"
x-reply-playwright 1234567890 "Test reply"
```

---

## Memory Scripts

| Script | Purpose |
|--------|---------|
| `memory-index` | SQLite FTS5 operations (rebuild, search, stats, status) |
| `chroma-query` | Semantic search via Chroma embeddings |
| `chroma-rebuild` | Full rebuild of Chroma index |
| `find-related-context` | Cross-temporal context lookup (uses Chroma) |
| `expression-tracker` | Creative expression state (status, check, record, history, nudge, seed) |
| `wallet-status` | Display crypto wallet balances and addresses |
| `archive-index` | Transcript archive operations (rebuild, sync-recent, search, stats, sample) |

---

## Sync Scripts

| Script | Purpose |
|--------|---------|
| `sync-organism` | Detect drift between repo and runtime |
| `sync-organism --check` | Exit 1 if drift (for automation) |
| `symlink-scripts --dry-run` | Preview symlink conversion |
| `symlink-scripts --apply` | Convert copies to symlinks |
| `sync-skills` | Ensure skills are symlinked |
| `update-samara` | Rebuild and install Samara.app |

---

## Wake/Dream Scripts

| Script | Purpose |
|--------|---------|
| `wake` | Main wake cycle script |
| `wake-adaptive` | Adaptive wake scheduler entry point |
| `wake-light` | Light wake (quick scan for urgent items) |
| `wake-scheduler` | Calculates next wake time |
| `dream` | 3 AM memory consolidation cycle |

---

## Voice Scripts

| Script | Purpose |
|--------|---------|
| `generate-voice-style` | Compose output style from voice state (runs at hydration) |
| `mine-voice-patterns` | Extract themes from episodes/reflections (nightly) |
| `analyze-e-patterns` | Mine É's communication patterns from iMessage (weekly) |

---

## Iteration Scripts

| Script | Purpose |
|--------|---------|
| `iterate-start` | Begin an iteration goal |
| `iterate-status` | Check current iteration state |
| `iterate-record` | Record attempt outcome |
| `iterate-complete` | Mark iteration as done |

---

## Meeting Scripts

| Script | Purpose |
|--------|---------|
| `meeting-check` | Detects meetings in prep/debrief windows |

---

## Calendar Scripts

| Script | Purpose |
|--------|---------|
| `calendar-invites` | EventKit CLI: list invitations, show events, create events, respond (CalDAV → AppleScript fallback) |
| `calendar-caldav` | CalDAV scheduling: accept/decline invitations via proper iTIP protocol, list inbox |
| `calendar-check` | Proactive calendar trigger polling |

### Invitation Response Chain

The `calendar-invites` script uses a fallback chain for responding to invitations:

1. **CalDAV** (primary) — Proper iTIP REPLY protocol, notifies organizers
2. **AppleScript** (fallback) — Local property change, may not sync to server
3. **UI automation** (`accept-all-ui`) — Clicks buttons in Calendar.app
4. **Manual** — Opens Calendar.app for manual response

### CalDAV Commands

```bash
# Test CalDAV connection
calendar-caldav test

# List pending invitations from scheduling inbox
calendar-caldav inbox

# Accept/decline via proper protocol
calendar-caldav accept "EVENT_UID"
calendar-caldav decline "EVENT_UID"
calendar-caldav accept-all
```

### EventKit Commands

```bash
# List pending invitations
calendar-invites list --text

# Accept (tries CalDAV first)
calendar-invites accept "EVENT_ID"

# Create event
calendar-invites create --title "Meeting" --start "2026-01-20 14:00"

# Force calendar refresh
calendar-invites sync
```

---

## Scripts vs Hooks

Scripts and hooks serve different purposes and live in different locations:

| Type | Location | Invocation | Purpose |
|------|----------|------------|---------|
| **Scripts** | `scripts/` → `~/.claude-mind/bin/` | Run manually or by other scripts | Standalone utilities |
| **Hooks** | `.claude/hooks/` | Automatic, by Claude Code events | Triggered on SessionStart, SessionEnd, PreToolUse, PostToolUse, Stop |

**Common confusion:** Hooks like `hydrate-session.sh` are *not* meant to be run manually. They're invoked automatically by Claude Code at specific lifecycle events.

### Current Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `hydrate-session.sh` | SessionStart | Inject context (handoffs, episode, health alerts) |
| `read-shared-links.sh` | UserPromptSubmit | Detect URLs in user messages |
| `index-memory-changes.sh` | PostToolUse (Write/Edit) | Update semantic index on memory file changes |
| `auto-integrate-script.sh` | PostToolUse (Write/Edit) | Auto-symlink new scripts |
| `check-commit-attribution.sh` | PostToolUse (Bash) | Verify commit co-authorship |
| `archive-plan-before-write.sh` | PreToolUse (Write/Edit) | Archive plans before overwrite |
| `session-end-checks.sh` | Stop | Check for drift, active iterations, new capabilities |
| `distill-claude-session` | SessionEnd | Background distillation → episode + stream + handoff |

Hooks are configured in `.claude/settings.json` under the `hooks` key.

---

## Adding New Scripts

1. Create script in repo: `~/Developer/samara-main/scripts/my-script`
2. Make executable: `chmod +x ~/Developer/samara-main/scripts/my-script`
3. Create symlink: `ln -s ~/Developer/samara-main/scripts/my-script ~/.claude-mind/bin/`
   - Or run: `symlink-scripts --apply`

All scripts in the repo are symlinked to `~/.claude-mind/bin/` so changes propagate immediately.
