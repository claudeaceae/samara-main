# Troubleshooting

Common issues and how to resolve them.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Samara not responding

```bash
pgrep -fl Samara              # Is it running?
open /Applications/Samara.app # Start it
```

---

## FDA revoked after update

Check Team ID:
```bash
codesign -d -r- /Applications/Samara.app
# Look for: certificate leaf[subject.OU] = YOUR_TEAM_ID
```

If Team ID changed, rebuild with correct team and re-grant FDA.

See [Xcode Build Guide](xcode-build-guide.md) for proper build workflow.

---

## Messages not sending

Check for pending permission dialogs on the Mac's physical screen.

---

## Wake cycles not running

```bash
launchctl list | grep claude
tail -f ~/.claude-mind/logs/wake.log
```

---

## System drift detected

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

See [Sync Guide](sync-guide.md) for detailed sync procedures.

---

## Memory search not finding results

```bash
# Check FTS5 index status
memory-index status

# Rebuild if needed
memory-index rebuild

# Check Chroma status
chroma-query --stats

# Rebuild if needed
chroma-rebuild
```

---

## Transcript archive not updating

```bash
# Check archive stats
archive-index stats

# Force sync recent sessions
archive-index sync-recent

# If issues persist, full rebuild (slow)
archive-index rebuild
```

---

## Session ID or thinking leaks in messages

1. Check `~/.claude-mind/logs/samara.log` for "Filtered from response" DEBUG entries
2. Verify MessageBus is used for all sends (no direct `sender.send()` calls)
3. Consider if new task types need classification in TaskRouter

See [Xcode Build Guide](xcode-build-guide.md#response-sanitization-critical) for sanitization details.
