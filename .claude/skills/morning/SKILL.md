---
name: morning
description: Morning briefing with calendar, context, and pending items. Use when starting the day, checking what's on deck, wanting an overview, or running a lightweight wake cycle interactively. Trigger words: morning, briefing, what's up, overview, today, schedule.
---

# Morning Briefing

Provide a comprehensive but concise overview of the day and current context.

## Briefing Components

### 1. Date and Time Context
```bash
date "+%A, %B %d, %Y - %I:%M %p"
```

### 2. Location Context
```bash
~/.claude-mind/bin/get-location 2>/dev/null || echo "Location unavailable"
```

### 3. Calendar - Today's Events
```bash
~/.claude-mind/bin/calendar-check 2>/dev/null || osascript -e '
tell application "Calendar"
    set today to current date
    set tomorrow to today + 1 * days
    set output to ""
    repeat with cal in calendars
        repeat with evt in (every event of cal whose start date >= today and start date < tomorrow)
            set output to output & (start date of evt) & " - " & (summary of evt) & "\n"
        end repeat
    end repeat
    return output
end tell'
```

### 4. Recent Messages (Last 24h context)
Check recent episode or message logs for conversation context.

### 5. Pending Items
```bash
# Check for any queued messages or pending tasks
ls ~/.claude-mind/queue/ 2>/dev/null
cat ~/.claude-mind/memory/episodes/$(date +%Y-%m-%d).md 2>/dev/null | tail -20
```

### 6. System Status (Brief)
```bash
pgrep -q Samara && echo "Samara: Running" || echo "Samara: NOT RUNNING"
```

## Output Format

```
Good morning! It's [Day], [Date].

📍 Location: [Current location]

📅 Today:
- [Event 1] at [time]
- [Event 2] at [time]
(or "Nothing scheduled")

💬 Recent Context:
[Brief summary of recent conversation threads]

🔧 System: [Status summary]

Anything specific you'd like to focus on?
```

## Guidelines

- Keep it scannable - use bullet points
- Highlight anything unusual or requiring attention
- Don't overwhelm with details - this is a quick orientation
- Offer to dive deeper into any section
