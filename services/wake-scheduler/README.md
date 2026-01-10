# Wake Scheduler Service

Calculates optimal wake times based on context, replacing rigid fixed schedules with adaptive scheduling.

## Purpose

Instead of only waking at fixed times (9 AM, 2 PM, 8 PM), the scheduler can:
- Wake early if a calendar event is approaching
- Wake early if high-priority messages are pending
- Dispatch light (30-second) wakes instead of full wakes when appropriate
- Skip unnecessary wakes when confidence is low

## Usage

```bash
# Check if should wake now
~/.claude-mind/bin/wake-scheduler check
# Returns: {"should_wake": true, "type": "full", "reason": "Scheduled 9:00 wake"}

# Get next scheduled wake time
~/.claude-mind/bin/wake-scheduler next
# Returns: {"next_scheduled": "2026-01-10T14:00:00", "minutes_until": 120, ...}

# Show full scheduler status
~/.claude-mind/bin/wake-scheduler status

# Record that a wake occurred
~/.claude-mind/bin/wake-scheduler record full
```

## Integration with Wake Scripts

The adaptive dispatcher `wake-adaptive` calls this scheduler:

```bash
# Run by launchd every 15 minutes
~/.claude-mind/bin/wake-adaptive

# Forces a specific wake type
~/.claude-mind/bin/wake-adaptive --force full
```

## Wake Types

| Type | Description | When Used |
|------|-------------|-----------|
| `full` | Full wake cycle (5+ min) | Scheduled times, high confidence triggers |
| `light` | Quick scan (30 sec) | Moderate confidence, just checking in |
| `emergency` | Immediate | High-priority external event |
| `none` | No wake | Low confidence, nothing urgent |

## Confidence Calculation

The scheduler calculates a confidence score (0.0 - 1.0) based on:

| Factor | Weight | Description |
|--------|--------|-------------|
| High-priority queue items | +0.4 | Messages marked as high/time_sensitive |
| Calendar event within 30 min | +0.5 | Upcoming meetings |
| Calendar event within 60 min | +0.3 | Slightly upcoming meetings |
| Time since last wake > 3 hours | +0.2 | Been too long |
| 3+ pending triggers | +0.3 | Multiple signals waiting |

**Thresholds:**
- Confidence ≥ 0.7 → Full wake
- Confidence ≥ 0.4 → Light wake
- Otherwise → No wake

## Configuration

The scheduler reads from these files:
- `~/.claude-mind/state/proactive-queue/queue.json` — Pending messages
- `~/.claude-mind/state/calendar-cache.json` — Upcoming events
- `~/.claude-mind/state/triggers/triggers.json` — Context triggers
- `~/.claude-mind/state/scheduler-state.json` — Internal state (auto-created)

## Base Schedule

The scheduler augments, not replaces, the base launchd schedule:

| Time | Behavior |
|------|----------|
| 9:00 AM (±15 min) | Always full wake |
| 2:00 PM (±15 min) | Always full wake |
| 8:00 PM (±15 min) | Always full wake |
| Other times | Based on confidence calculation |

## Files

- `scheduler.py` — Main scheduler logic
- `~/.claude-mind/bin/wake-scheduler` — Bash wrapper

## Minimum Wake Interval

To prevent wake storms, there's a 60-minute minimum between wakes.
