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

### Three-Location Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  REPO (~/Developer/samara-main/)                                │
│  The "genome" - portable, shareable, version-controlled         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ .claude/                                                  │   │
│  │   ├── agents/     ←──┬──── ~/.claude/agents (global)     │   │
│  │   ├── hooks/         │                                    │   │
│  │   ├── skills/     ←──┼──── ~/.claude/skills/* (global)   │   │
│  │   └── settings.json  └──── ~/.claude-mind/.claude (runtime)│  │
│  │                                                           │   │
│  │ scripts/          ←────── ~/.claude-mind/bin/* (runtime)  │   │
│  │ CLAUDE.md         ←────── ~/.claude-mind/CLAUDE.md        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  RUNTIME (~/.claude-mind/)                                      │
│  The "organism" - accumulates memories, adapts, grows           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ .claude → repo/.claude     (symlink - hooks/skills/agents)│   │
│  │ CLAUDE.md → repo/CLAUDE.md (symlink)                      │   │
│  │ bin/* → repo/scripts/*     (individual symlinks)          │   │
│  │ memory/                    (NOT symlinked - accumulates)  │   │
│  │ state/                     (NOT symlinked - runtime state)│   │
│  │ config.json                (NOT symlinked - instance cfg) │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  GLOBAL (~/.claude/)                                            │
│  Claude Code's home - read from ANY directory                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ agents → repo/.claude/agents  (symlink)                   │   │
│  │ skills/* → repo/.claude/skills/* (individual symlinks)    │   │
│  │ settings.json                 (NOT symlinked - global cfg)│   │
│  │ projects/                     (conversation logs)         │   │
│  │ plugins/                      (installed plugins)         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Symlink Summary Table

| Component | Symlinked? | Location | Reason |
|-----------|------------|----------|--------|
| Scripts (`bin/`) | ✅ Yes | Runtime | Canonical in repo, changes propagate |
| Skills (`.claude/skills/`) | ✅ Yes | Global + Runtime | Canonical in repo |
| Agents (`.claude/agents/`) | ✅ Yes | Global | Canonical in repo |
| Hooks (`.claude/hooks/`) | ✅ Yes | Via `.claude/` symlink | Canonical in repo |
| Runtime `.claude/` | ✅ Yes | Runtime | Project settings when invoked from runtime |
| Runtime `CLAUDE.md` | ✅ Yes | Runtime | Instructions when invoked from runtime |
| Instructions (`instructions/`) | ✅ Yes | Runtime | Canonical in repo, prompt guidance |
| Memory files | ❌ No | Runtime | Instance-specific, accumulates |
| Config (`config.json`) | ❌ No | Runtime | Instance-specific |
| State files | ❌ No | Runtime | Runtime state |
| Expression seeds | ❌ No | Runtime | Can be customized per instance |
| Samara.app | N/A | /Applications | Built binary, use `update-samara` |

### Why This Architecture?

**When Samara invokes Claude Code:**
- Working directory: `~/.claude-mind/`
- Reads: global `~/.claude/settings.json` + project `~/.claude-mind/.claude/settings.json`
- Result: All hooks, agents, and skills are available

**When human runs Claude in the repo:**
- Working directory: `~/Developer/samara-main/`
- Reads: global + project `.claude/settings.json`
- Result: All hooks, agents, and skills are available

**When human runs Claude elsewhere:**
- Working directory: some other project
- Reads: only global `~/.claude/settings.json`
- Result: Skills and agents available, but organism-specific hooks NOT active (this is intentional - hooks like `hydrate-session` only make sense for the organism)

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
