# Architecture Drift Analysis

*Created: 2026-01-05 after the TCC Camera Permission incident*

## The Discovery

While investigating why the webcam worked in direct Claude Code sessions but failed when invoked via Samara (iMessage), we discovered a massive delta between the "encoded system" (what's in the repo) and the "running system" (what's actually deployed).

## The Three-Part Architecture

The system consists of three separate concerns:

| Component | Location | Purpose | Updates |
|-----------|----------|---------|---------|
| **Repo** | `~/Developer/samara-main/` | Source code, templates, documentation | Git commits |
| **Runtime** | `~/.claude-mind/` | Scripts, memory, config, state | Organic changes |
| **App** | `/Applications/Samara.app` | Built binary | `update-samara` script |

## Why Separation Exists

This is a "DNA vs. Organism" pattern:

- **Repo** = The genome. Portable, version-controlled, shareable.
- **Runtime** = The living organism. Accumulates memories, adapts, evolves.
- **App** = The body. Physical manifestation with its own identity.

The separation is intentional:
1. Repo can be cloned to birth a new Claude organism
2. Runtime contains instance-specific data (memories, sessions)
3. App needs stable code signing identity for FDA

## Current Sync Mechanisms

### What Works (Symlinks)

**Skills** are properly symlinked:
```
~/.claude/skills/morning → ~/Developer/samara-main/.claude/skills/morning/
~/.claude/skills/status  → ~/Developer/samara-main/.claude/skills/status/
... (all 10 skills)
```

Changes to skills in the repo are immediately visible to the running system.

### What Doesn't Work (Copies)

**Scripts** are copied during `birth.sh`:
```bash
cp -r "$SCRIPT_DIR/scripts/"* "$TARGET_DIR/bin/"  # One-time copy
```

Changes diverge bidirectionally:
- Repo scripts: 20 files (stale)
- Runtime scripts: 46 files (evolved)

### What Requires Manual Rebuild

**Samara.app** must be rebuilt with `update-samara`:
```bash
~/.claude-mind/bin/update-samara  # Archive, export, notarize, install
```

## The Drift Discovered

### Script Divergence

| Script | Repo Version | Runtime Version |
|--------|--------------|-----------------|
| `wake` | Basic wake cycle | + Question synthesizer, proactive questioning |
| `dream` | Basic dream cycle | + Location pattern learning, trip summaries |
| `look` | (doesn't exist) | Webcam capture with Samara fallback |
| `message` | Basic send | (same) |
| 26 scripts | (don't exist) | Created organically in runtime |

### Configuration Divergence

- `ClaudeInvoker.swift` working directory was `/` (repo) vs. needed to be `~/.claude-mind`
- This meant project-specific features (CLAUDE.md, hooks, agents) weren't loaded

### Feature Divergence

- Camera capture required native AVFoundation in Samara (not just CLI tools)
- TCC permissions don't inherit through subprocess chains

## Root Causes

1. **No ongoing sync mechanism** - Birth is one-time, no "rebirth" or "sync"
2. **Bidirectional development** - Changes made in both repo and runtime
3. **Missing propagation** - `update-samara` only rebuilds app, not scripts
4. **Organic growth** - New scripts created in runtime, never added to repo

## Impact

When Claude runs from a different context (Samara vs. Terminal):
- Different scripts available
- Different CLAUDE.md context
- Different session storage
- Different capability expectations

## Solutions

### Short-term: Sync Scripts to Repo

1. Copy evolved runtime scripts → repo
2. Update repo scripts to match runtime
3. Document which scripts are canonical where

### Medium-term: Symlink Scripts Like Skills

```bash
# In birth.sh, instead of:
cp -r "$SCRIPT_DIR/scripts/"* "$TARGET_DIR/bin/"

# Do:
ln -s "$SCRIPT_DIR/scripts" "$TARGET_DIR/bin"

# Or symlink individual scripts:
for script in "$SCRIPT_DIR/scripts/"*; do
    ln -s "$script" "$TARGET_DIR/bin/$(basename $script)"
done
```

### Long-term: Unified Development

1. All development happens in repo
2. Runtime is purely a view (symlinks + instance data)
3. `update-organism` script that:
   - Validates symlinks
   - Rebuilds Samara if needed
   - Shows drift report
   - Can be run from wake cycles

## Implementation Status (2026-01-05)

All recommendations have been implemented:

### ✅ 1. Created `sync-organism` Script

Located at `scripts/sync-organism`. Detects drift and reports:
- Samara.app signing verification (correct Team ID)
- Skills symlink status
- Script differences between repo and runtime
- Samara source vs. installed app

### ✅ 2. Added Drift Check to Wake Cycle

Every wake cycle now runs `sync-organism --check` and injects a warning into Claude's prompt if drift is detected. See `scripts/wake` lines 87-100.

### ✅ 3. Documented Expected Divergence

See CLAUDE.md "Keeping the System in Sync" section.

**Should diverge (instance-specific):**
- `config.json`
- `memory/*`
- `state/*`
- `logs/*`

**Should NOT diverge (now symlinked):**
- Scripts (`bin/*`)
- Skills (`.claude/skills/`)
- Hooks (`.claude/hooks/`)

### ✅ 4. Scripts Now Symlinked

All 48 scripts are symlinked from runtime to repo:
```
~/.claude-mind/bin/wake → ~/Developer/samara-main/scripts/wake
```

Use `symlink-scripts --apply` after adding new scripts to repo.

### ✅ 5. Claude Code Hooks

- `PreToolUse` hook blocks dangerous DerivedData copies
- `Stop` hook warns about drift at session end

## Conclusion

The separation between repo and runtime is intentional and now properly managed:

| Component | Sync Method | Status |
|-----------|-------------|--------|
| Skills | Symlinked to repo | ✅ Working |
| Scripts | Symlinked to repo | ✅ Working (fixed 2026-01-05) |
| Hooks | Symlinked via `.claude/` | ✅ Working |
| Samara.app | `update-samara` script | ✅ Working |
| Memory files | Not synced (intentional) | ✅ Correct |

The TCC camera permission incident was a symptom of a larger architectural gap. That gap has now been fully addressed through:
1. Native AVFoundation camera capture in Samara
2. Symlinked scripts eliminating drift
3. Automated drift detection in wake cycles
4. Comprehensive documentation in CLAUDE.md

Future organisms born from this repo will inherit these safeguards.
