# Sync Guide

Keeping repo, runtime, and app synchronized.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## The Problem

The repo and runtime can drift apart:
- Scripts edited in runtime don't propagate to repo
- Repo changes don't propagate to runtime (if using copies)
- Samara.app can become stale vs. source code

---

## The Solution: Symlinks + Automated Detection

### Scripts are symlinked from runtime to repo:

```
~/.claude-mind/bin/wake → ~/Developer/samara-main/scripts/wake
```

This means:
- Edit `~/Developer/samara-main/scripts/wake` → runtime sees it immediately
- No manual sync needed for existing scripts
- New scripts: add to repo, run `symlink-scripts --apply`

### Drift detection is automated:

- Every wake cycle runs `sync-organism --check`
- Claude Code Stop hook warns at session end
- `/sync` skill for manual checks

---

## Sync Tools

| Tool | Purpose |
|------|---------|
| `sync-organism` | Detect drift between repo and runtime |
| `sync-organism --check` | Exit 1 if drift (for automation) |
| `symlink-scripts --dry-run` | Preview symlink conversion |
| `symlink-scripts --apply` | Convert copies to symlinks |
| `sync-skills` | Ensure skills are symlinked |
| `update-samara` | Rebuild and install Samara.app |

---

## What Should Be Symlinked

| Component | Symlinked? | Reason |
|-----------|------------|--------|
| Scripts (`bin/`) | ✅ Yes | Canonical in repo, changes propagate |
| Skills (`.claude/skills/`) | ✅ Yes | Canonical in repo |
| Hooks (`.claude/hooks/`) | ✅ Yes | Via `.claude/` symlink |
| Instructions (`instructions/`) | ✅ Yes | Canonical in repo, prompt guidance |
| Memory files | ❌ No | Instance-specific, accumulates |
| Config (`config.json`) | ❌ No | Instance-specific |
| State files | ❌ No | Runtime state |
| Expression seeds | ❌ No | Can be customized per instance |
| Samara.app | N/A | Built binary, use `update-samara` |

---

## Adding New Scripts

1. Create script in repo: `~/Developer/samara-main/scripts/my-script`
2. Make executable: `chmod +x ~/Developer/samara-main/scripts/my-script`
3. Create symlink: `ln -s ~/Developer/samara-main/scripts/my-script ~/.claude-mind/bin/`
   - Or run: `symlink-scripts --apply`

---

## Workflow for Script Changes

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

---

## Fixing Drift

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
