---
name: sync
description: Check for drift between repo and running system. Use when checking if scripts or Samara are out of sync, verifying system integrity, or before/after rebuilds. Trigger words: sync, organism sync, check drift, system drift, repo sync.
context: fork
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Sync Skill

Check for drift between the repo and running system, and optionally fix it.

## What This Does

Runs the `sync-organism` script to detect differences between:
- `~/Developer/samara-main/` (the repo/genome)
- `~/.claude-mind/` (the running organism)
- `/Applications/Samara.app` (the built app)

## Running the Check

```bash
~/.claude-mind/system/bin/sync-organism
```

## What It Checks

1. **Samara.app Signing** - Correct Team ID (G4XVD3J52J)
2. **Skills Symlinks** - All skills properly linked from repo
3. **Script Drift** - Differences between repo and runtime scripts
4. **Samara Source** - Whether installed app matches source code

## When to Use

- After making changes to scripts in either location
- Before/after `update-samara` rebuilds
- During wake cycles (for monitoring)
- When something "should work but doesn't"

## Output Example

```
## Samara.app Signing
[OK] Samara.app signed with correct Team ID: G4XVD3J52J

## Skills Symlinks
[OK] 10 skills properly symlinked

## Script Drift Analysis
[OK] All shared scripts are identical

## Samara.app Source Check
[OK] Samara.app is up to date with source

SUMMARY
Total drift: 0 issues
```

## Fixing Drift

If drift is detected, the script shows commands to fix it. Common fixes:
- Copy runtime script to repo: `cp ~/.claude-mind/system/bin/X ~/Developer/samara-main/scripts/`
- Rebuild Samara: `~/.claude-mind/system/bin/update-samara`
- Recreate symlinks: Run `sync-skills` or manually create symlinks
