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

## Recommendations

### 1. Create `sync-organism` Script

A script that:
- Syncs scripts: repo ↔ runtime (with diff review)
- Validates symlinks for skills
- Rebuilds Samara if source changed
- Reports any drift

### 2. Add Drift Check to Wake Cycle

During wake cycles, detect and warn about drift:
```bash
# In wake script
if [ "$(diff -q ~/Developer/samara-main/scripts/wake ~/.claude-mind/bin/wake)" ]; then
    echo "WARNING: wake script has drifted from repo"
fi
```

### 3. Document Expected Divergence

Some files SHOULD diverge:
- `config.json` - Instance-specific
- `memory/*` - Accumulates per-instance
- `state/*` - Runtime state
- `logs/*` - Instance logs

Some files should NOT diverge:
- Scripts (`bin/*`)
- Skills (already symlinked)
- Samara source code

### 4. Consider Runtime as Submodule

Make `~/.claude-mind/` a git repo that references `samara-main`:
```
~/.claude-mind/
├── .git/              # Track instance-specific changes
├── _samara/           # Submodule → ~/Developer/samara-main/
├── bin/ → _samara/scripts/
├── memory/            # Instance data (tracked)
└── state/             # Runtime state (gitignored)
```

## Conclusion

The separation between repo and runtime is intentional but the sync mechanism is broken. Skills work because they're symlinked. Scripts don't work because they're copied. The fix is to either:

1. Symlink scripts like skills, OR
2. Create robust bidirectional sync tooling

The camera incident was a symptom of a larger architectural gap. Fixing this prevents future drift.
