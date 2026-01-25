# Meeting Check Service

Detects upcoming and recently ended calendar events, generating sense events for proactive meeting prep and post-meeting debriefs.

## Overview

This service runs every 15 minutes via launchd and:
1. Checks for meetings starting in 10-20 minutes (prep window)
2. Checks for meetings that ended 0-30 minutes ago (debrief window)
3. Writes sense events to `~/.claude-mind/system/senses/` for SenseRouter to process

## Installation

```bash
# Copy plist to LaunchAgents
cp com.claude.meeting-check.plist ~/Library/LaunchAgents/

# Load the service
launchctl load ~/Library/LaunchAgents/com.claude.meeting-check.plist

# Verify it's running
launchctl list | grep meeting-check
```

## Configuration

Preferences are stored in `~/.claude-mind/state/meeting-prefs.json`:

```json
{
  "debrief_all_events": true,
  "skip_calendars": ["Claude", "Birthdays", "US Holidays"],
  "skip_patterns": ["Lunch", "Break", "Block", "Focus"],
  "prep_cooldown_min": 60,
  "debrief_cooldown_min": 240
}
```

- `skip_calendars`: Calendar names to ignore
- `skip_patterns`: Event title patterns to ignore (case-insensitive)
- `prep_cooldown_min`: Minimum minutes between prep events for same meeting
- `debrief_cooldown_min`: Minimum minutes between debrief events for same meeting

## Sense Events

### meeting_prep

Generated 10-20 minutes before a meeting:

```json
{
  "sense": "meeting_prep",
  "timestamp": "2026-01-13T14:45:00",
  "priority": "normal",
  "data": {
    "event_title": "Weekly Sync",
    "start_time": "2026-01-13T15:00:00",
    "minutes_until": 15,
    "location": "Zoom",
    "calendar": "Work",
    "attendees": [
      {"email": "lucy@example.com", "name": "Lucy"}
    ]
  }
}
```

### meeting_debrief

Generated 0-30 minutes after a meeting ends:

```json
{
  "sense": "meeting_debrief",
  "timestamp": "2026-01-13T16:15:00",
  "priority": "normal",
  "data": {
    "event_title": "Weekly Sync",
    "ended_at": "2026-01-13T16:00:00",
    "minutes_since_end": 15,
    "duration_min": 60,
    "location": "Zoom",
    "calendar": "Work",
    "attendees": [{"email": "lucy@example.com", "name": "Lucy"}],
    "attendee_names": ["Lucy"]
  }
}
```

## Logs

- Log file: `~/.claude-mind/system/logs/meeting-check.log`
- stdout: `~/.claude-mind/system/logs/meeting-check.stdout.log`
- stderr: `~/.claude-mind/system/logs/meeting-check.stderr.log`

## Manual Testing

```bash
# Run manually
~/.claude-mind/system/bin/meeting-check

# Check logs
tail -f ~/.claude-mind/system/logs/meeting-check.log

# Check for generated sense events
ls -la ~/.claude-mind/system/senses/meeting_*.event.json
```

## Dependencies

- Python 3 with virtual environment at `~/.claude-mind/.venv`
- `lib/calendar_analyzer.py` for calendar access
- Samara.app running for sense event processing
