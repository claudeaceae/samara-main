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

## Adding New Scripts

1. Create script in repo: `~/Developer/samara-main/scripts/my-script`
2. Make executable: `chmod +x ~/Developer/samara-main/scripts/my-script`
3. Create symlink: `ln -s ~/Developer/samara-main/scripts/my-script ~/.claude-mind/bin/`
   - Or run: `symlink-scripts --apply`

All scripts in the repo are symlinked to `~/.claude-mind/bin/` so changes propagate immediately.
