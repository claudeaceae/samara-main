---
name: samara
description: Debug, check, or restart Samara.app - the message broker. Use when messages aren't being detected, Samara crashed, need to view logs, check Full Disk Access, or restart the app. Trigger words: samara, messages not working, restart, logs, FDA, broker.
---

# Samara Debug and Control

Diagnose and manage Samara.app, the message broker that connects iMessage to Claude.

## Quick Actions

### Check if Running
```bash
pgrep -fl Samara
ps aux | grep -i [S]amara
```

### View Recent Logs
```bash
# Samara's own logs
tail -50 ~/.claude-mind/logs/samara.log 2>/dev/null

# System logs for Samara
log show --predicate 'process == "Samara"' --last 5m 2>/dev/null | tail -30
```

### Restart Samara
```bash
# Kill if running
pkill -f Samara

# Wait a moment
sleep 2

# Relaunch
open /Applications/Samara.app
```

### Check Full Disk Access
```bash
# This will work if FDA is granted
ls ~/Library/Messages/chat.db && echo "FDA: OK" || echo "FDA: MISSING"

# Check code signature (Team ID must be stable)
codesign -d -r- /Applications/Samara.app 2>&1 | head -5
```

## Common Issues

### Messages Not Being Detected
1. Check Samara is running
2. Check FDA is intact
3. Check chat.db is readable
4. Look for errors in logs

### Samara Crashed
1. Check system logs for crash reason
2. Restart with `open /Applications/Samara.app`
3. If repeated crashes, may need rebuild

### FDA Revoked After Update
This happens if Team ID changed during rebuild:
```bash
# Check current signature
codesign -dv /Applications/Samara.app 2>&1 | grep TeamIdentifier

# If Team ID is wrong, need to:
# 1. Rebuild with correct team in Xcode
# 2. Re-grant FDA in System Settings
```

### Rebuild Samara
```bash
~/.claude-mind/bin/update-samara
```
This archives, exports, and installs the latest version.

## Diagnostic Report

When troubleshooting, gather:
1. Is Samara running?
2. FDA status
3. Recent log errors
4. Last successful message detection
5. Code signature validity

Present findings clearly with recommended actions.
