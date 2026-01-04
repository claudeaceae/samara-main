---
name: status
description: System health check for Samara organism. Use when checking if Samara is running, if messages are being detected, if wake cycles are scheduled, or diagnosing permission issues. Trigger words: status, health, check, running, working, broken.
---

# System Status Check

Perform a comprehensive health check of the Samara organism infrastructure.

## Checks to Perform

### 1. Samara.app Status
```bash
pgrep -fl Samara
```
- If not running, note this as critical
- If running, check how long it's been up

### 2. Recent Message Detection
```bash
# Check if Samara has logged recent message detection
tail -20 ~/.claude-mind/logs/samara.log 2>/dev/null || echo "No Samara log found"
```

### 3. Wake Cycle Schedule
```bash
launchctl list | grep claude
```
Check that these are loaded:
- com.claude.wake-morning
- com.claude.wake-afternoon
- com.claude.wake-evening
- com.claude.dream

### 4. Recent Wake/Dream Logs
```bash
tail -10 ~/.claude-mind/logs/wake.log 2>/dev/null
tail -10 ~/.claude-mind/logs/dream.log 2>/dev/null
```

### 5. Lock File Status
```bash
ls -la ~/.claude-mind/claude.lock 2>/dev/null || echo "No lock file (good)"
```
A stale lock file can block operations.

### 6. Full Disk Access Check
```bash
# Try to read chat.db - will fail without FDA
ls -la ~/Library/Messages/chat.db 2>/dev/null && echo "FDA appears intact"
```

### 7. Disk Space
```bash
df -h ~ | tail -1
```

## Output Format

Summarize findings as:
- **Samara**: Running/Not Running
- **Wake Cycles**: All loaded / Missing X
- **Last Wake**: timestamp
- **Last Dream**: timestamp
- **FDA Status**: OK / Issue
- **Lock File**: Clear / Stale
- **Disk**: X% used

Flag any issues that need attention.
