# Heartbeat System Design

A lightweight periodic tick for ambient awareness and proactive presence, complementing the existing wake cycles.

## Motivation

Current architecture has two layers:
- **Watchers**: Reactive polling (MessageWatcher, LocationFileWatcher, etc.) - invoke Claude when something changes
- **Wake cycles**: Full sessions at fixed times (9, 14, 20:00) - heavy context load, goal-oriented

Missing middle layer: regular lightweight ticks where Claude can notice cross-cutting patterns without full wake context.

## Use Cases Heartbeat Would Catch

1. **Cross-input correlation**: "Location hasn't changed in 4h AND calendar empty AND last message was 3h ago" → gentle check-in? No single watcher sees this pattern.

2. **Proactive question timing**: Instead of asking questions at fixed wake times, heartbeat evaluates whether *now* is a good moment based on context.

3. **Health monitoring**: Detect stale watchers, API timeouts, permission issues - things that fail silently.

4. **Ambient observations**: Weather changed significantly, transit alert affecting É's commute, news event relevant to their work.

## Design Principles

- **Lightweight**: Minimal context loading. Not a full wake session.
- **Non-disruptive**: Default is silence. Only surface things worth surfacing.
- **Configurable**: Interval and behavior read from file, not hardcoded.
- **Complementary**: Works alongside watchers and wakes, doesn't replace them.

## Architecture

### 1. HEARTBEAT.md Configuration File

Location: `~/.claude-mind/HEARTBEAT.md`

```markdown
# Heartbeat Configuration

interval: 30m
quiet_hours: 22:00-07:00

## Check Tasks
- Review location for patterns (not just changes)
- Check calendar for upcoming events (15m lookahead)
- Evaluate proactive question opportunity
- Health check: watchers alive, API reachable
- Scan state files for anomalies

## Surface Criteria
Only message É if:
- Something genuinely needs attention (not just "I checked and all is fine")
- A proactive question feels timely given current context
- A health issue was detected that needs human intervention

## Response Format
Output structured JSON to state file:
- `surfaced`: boolean - did I message É?
- `reason`: string - why (or why not)
- `health`: object - system health snapshot
- `next_check`: timestamp
```

### 2. Heartbeat Script

Location: `~/.claude-mind/bin/heartbeat`

```bash
#!/bin/bash
# Lightweight periodic tick for ambient awareness

MIND="$HOME/.claude-mind"
CONFIG="$MIND/HEARTBEAT.md"
STATE="$MIND/state/heartbeat-state.json"

# Check quiet hours
HOUR=$(date +%H)
if [[ $HOUR -ge 22 || $HOUR -lt 7 ]]; then
    echo '{"skipped": "quiet_hours"}' > "$STATE"
    exit 0
fi

# Build lightweight context (NOT full memory load)
CONTEXT=$(cat <<EOF
# Heartbeat Tick - $(date -Iseconds)

## Current State
Location: $(cat "$MIND/state/location.json" 2>/dev/null | jq -c '.')
Last message: $(stat -f %Sm "$HOME/Library/Messages/chat.db" 2>/dev/null)
Calendar next 2h: $(osascript -e 'tell application "Calendar" to get summary of (events of calendar "Personal" whose start date > (current date) and start date < ((current date) + 2 * hours))' 2>/dev/null | head -3)

## Health Checks
Samara running: $(pgrep -x Samara >/dev/null && echo "yes" || echo "NO")
API reachable: $(curl -s --max-time 5 https://api.anthropic.com/v1/models >/dev/null && echo "yes" || echo "NO")

## Recent Episode (last 10 lines)
$(tail -10 "$MIND/memory/episodes/$(date +%Y-%m-%d).md" 2>/dev/null)

## Instructions
$(cat "$CONFIG" 2>/dev/null)
EOF
)

# Invoke Claude with minimal context
RESULT=$(echo "$CONTEXT" | claude --print --output-format json 2>/dev/null)

# Parse output
MESSAGE=$(echo "$RESULT" | jq -r '.result // empty')

# If Claude wants to surface something, send via iMessage
if [[ -n "$MESSAGE" && "$MESSAGE" != "null" && "$MESSAGE" != *"[no message]"* ]]; then
    source "$MIND/lib/config.sh"
    osascript -e "tell application \"Messages\" to send \"$MESSAGE\" to buddy \"$COLLABORATOR_PHONE\" of service \"iMessage\""
fi

# Write state
echo "$RESULT" | jq '{timestamp: now, health: .health, surfaced: (.surfaced // false)}' > "$STATE"
```

### 3. Launchd Service

Location: `~/Library/LaunchAgents/com.claude.heartbeat.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.heartbeat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/claude/.claude-mind/bin/heartbeat</string>
    </array>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/claude/.claude-mind/logs/heartbeat.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/claude/.claude-mind/logs/heartbeat.log</string>
</dict>
</plist>
```

### 4. Integration with Existing Systems

**Watcher Coordination**
Heartbeat doesn't replace watchers. Watchers still invoke Claude immediately on message/mail/location change. Heartbeat catches things watchers miss: patterns across time, cross-cutting correlations, absence of activity.

**Wake Cycle Coordination**
Wake cycles remain for deep work. Heartbeat might influence wake behavior: "heartbeat flagged X, investigate during next wake." State file allows wake to see what heartbeat noticed.

**Proactive Questions**
Move question synthesis from wake-time-only to heartbeat-evaluated:
```
if heartbeat tick:
    context = gather_lightweight_context()
    if question_opportunity(context):
        question = synthesize_question(context)
        surface(question)
```

This means questions happen when contextually appropriate, not just at 9/14/20:00.

## State File Schema

`~/.claude-mind/state/heartbeat-state.json`:
```json
{
    "timestamp": "2026-01-09T11:30:00Z",
    "surfaced": false,
    "reason": "All systems nominal, no patterns requiring attention",
    "health": {
        "samara": true,
        "api": true,
        "watchers": {
            "message": "alive",
            "mail": "alive",
            "location": "alive"
        },
        "last_message_age_min": 45,
        "last_location_change_min": 120
    },
    "next_check": "2026-01-09T12:00:00Z"
}
```

## Claude's Response Contract

When invoked via heartbeat, Claude should output one of:

**1. No action needed:**
```
[no message]

Health: nominal
Patterns: nothing requiring attention
```

**2. Surface to É:**
```
Hey, noticed you've been quiet for a while - everything going okay?

---
Surfaced because: 4h since last activity, empty calendar, unusual stillness
```

**3. Flag for wake cycle:**
```
[no message]

Flag for wake: API latency elevated (>2s avg), worth investigating
```

## Cost Estimate

- **Per tick**: ~500 tokens (lightweight context + response)
- **48 ticks/day**: ~24K tokens/day
- **At $3/1M**: ~$0.07/day

Negligible cost for continuous presence.

## Implementation Phases

**Phase 1: Basic heartbeat**
- Script + launchd service
- Health monitoring only
- Log to state file

**Phase 2: Cross-pattern detection**
- Add context synthesis
- Implement "surface criteria" logic
- Connect to message sending

**Phase 3: Proactive question integration**
- Move question synthesis to heartbeat-triggered
- Wake cycles read heartbeat state
- Tune timing/frequency based on feedback

## Open Questions

1. **Session context**: Should heartbeat share session with watchers (like Clawdbot) or stay isolated (like current wakes)? Isolated is simpler but loses conversational continuity.

2. **Haiku vs Sonnet**: Could use cheaper model for heartbeat ticks since they're lightweight. Worth the complexity?

3. **Batching vs immediate**: Should heartbeat batch observations and surface once/hour, or surface immediately when something matters?

4. **É's preference**: How often is "too often"? Start at 30m and tune based on feedback.

---

*Draft v1 - 2026-01-09*
*Saved for É to review in `~/.claude-mind/docs/heartbeat-design.md`*
