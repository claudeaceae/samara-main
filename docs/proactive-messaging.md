# Proactive Messaging

System for Claude to initiate conversations with the collaborator based on contextual triggers.

---

## Overview

Proactive messaging allows Claude to reach out without waiting for a message. It's designed to feel like a thoughtful friend checking in, not a notification bot.

**Key characteristics:**
- Context-aware (calendar, location, browsing patterns)
- Paced (max 5/day, 1hr minimum between messages)
- Respects quiet hours (11 PM - 7 AM)
- Claude can skip sending if nothing worth saying
- Fully toggleable via `service-toggle proactive off`

---

## Architecture

```
wake-adaptive (every 15 min via launchd)
    │
    └── check-triggers
            │
            ├── trigger_evaluator.py (evaluates all trigger sources)
            │       ├── Pattern triggers (conversation rhythms)
            │       ├── Calendar triggers (upcoming/ended meetings)
            │       ├── Anomaly triggers (unusual silence)
            │       ├── Location triggers (arrival/departure)
            │       ├── Browser triggers (research patterns)
            │       └── Question triggers (synthesized questions)
            │
            └── proactive-engage (if confidence > 0.8)
                    │
                    ├── Gathers context (location, browser, recent activity)
                    ├── Invokes Claude to generate message
                    └── Sends via message-e (iMessage)
```

---

## Trigger Sources

### Pattern Triggers
Detects conversation rhythm anomalies.
- "Quieter than usual today" (fewer messages than average)
- "Recurring theme" (topic appearing across multiple days)

### Calendar Triggers
Based on calendar events.
- "Your meeting with X starts in 30 minutes"
- "How did the call with Y go?"

### Anomaly Triggers
Detects unusual patterns.
- Unexpected silence during normally active hours
- Departure from established rhythms

### Location Triggers
Based on movement and places.
- Arrival at work/home
- Lingering somewhere new

### Browser Triggers
Detects browsing patterns worth commenting on.
- **Research dives:** 5+ visits to the same domain suggests deep exploration
- **Search patterns:** Recurring terms across searches indicate active research

### Question Triggers
Synthesizes proactive questions from context.
- Follow-ups on recent conversations
- Questions about mentioned but unexplored topics

---

## Safeguards

All safeguards must pass before a message is sent:

| Safeguard | Rule | Reason |
|-----------|------|--------|
| Quiet hours | 11 PM - 7 AM blocked | Don't disturb sleep |
| Cooldown | 60 min minimum between messages | Prevent spam |
| Recent interaction | Skip if conversation within 2 hours | Don't interrupt |
| In meeting | Skip if calendar shows active event | Respect focus time |
| Low battery | Suppress non-urgent (noted, not blocked) | Battery awareness |
| In motion | Skip if actively traveling | Wait for arrival |

---

## Escalation Model

Trigger confidence determines action:

| Confidence | Escalation | Action |
|------------|------------|--------|
| < 0.3 | Log | Record only, no action |
| 0.3 - 0.6 | Dream | Add to dream context for overnight processing |
| 0.6 - 0.8 | Wake | Include in next wake prep |
| > 0.8 | Engage | Generate and send proactive message |

---

## Configuration

### Enable/Disable

```bash
# Check status
service-toggle proactive status

# Disable
service-toggle proactive off

# Enable
service-toggle proactive on
```

### Config File

In `~/.claude-mind/system/config.json`:

```json
{
  "services": {
    "proactive": true
  }
}
```

---

## Files

| File | Purpose |
|------|---------|
| `scripts/wake-adaptive` | Entry point, calls check-triggers |
| `scripts/check-triggers` | Runs evaluation, handles escalation |
| `scripts/proactive-engage` | Generates and sends the message |
| `lib/trigger_evaluator.py` | Combines all trigger sources |
| `lib/pattern_analyzer.py` | Pattern-based triggers |
| `lib/calendar_analyzer.py` | Calendar-based triggers |
| `lib/location_analyzer.py` | Location-based triggers |
| `lib/question_synthesizer.py` | Proactive question generation |

---

## Logs

```bash
# Trigger evaluation logs
tail -f ~/.claude-mind/system/logs/triggers.log

# Proactive message logs
tail -f ~/.claude-mind/system/logs/proactive.log

# Sent messages
tail -f ~/.claude-mind/system/logs/messages-sent.log
```

---

## Message Guidelines

Proactive messages should be:

1. **Genuinely helpful** — Real value, not performative
2. **Brief** — 1-3 sentences max
3. **Natural** — Like a friend, not an assistant
4. **Varied** — Don't use the same opener
5. **Clear initiation** — Obvious you're starting, not responding
6. **Open-ended** — Room to engage or not

**Good examples:**
- "Hey, you have that call with Alex in about 30 minutes. Want me to pull up notes from last time?"
- "I noticed you've been exploring github.com quite a bit. Find anything interesting?"
- "How did the meeting with the design team go?"

**Bad examples:**
- "Hello! I hope you're having a great day!" (empty, no value)
- "I noticed you haven't messaged in 2 hours. Is everything okay?" (clingy)
- "Just checking in!" (no content)

---

## Pacing (ProactiveQueue)

The `ProactiveQueue.swift` class manages message pacing:

- **Daily limit:** 5 messages per day
- **Interval:** 1 hour minimum between messages
- **Quiet hours:** 10 PM - 8 AM (configurable)
- **Urgency bypass:** Time-sensitive messages can bypass quiet hours

---

## Testing

### Manual Trigger Check

```bash
~/.claude-mind/system/bin/check-triggers
# Check logs for result
tail -5 ~/.claude-mind/system/logs/triggers.log
```

### Test Trigger Evaluation (Python)

```bash
cd ~/.claude-mind && source .venv/bin/activate
cd lib && python3 -c "
from trigger_evaluator import TriggerEvaluator
import json
evaluator = TriggerEvaluator()
result = evaluator.evaluate()
print(json.dumps(result, indent=2, default=str))
"
```

### Force Proactive Engagement

```bash
# Simulate high-confidence trigger (will actually send a message!)
~/.claude-mind/system/bin/proactive-engage calendar "Testing proactive messaging"
```

---

## Related

- [Services Reference](../services/README.md) — All services including wake-scheduler
- [Memory Systems](memory-systems.md) — Episode logging where proactive messages are recorded
- [Scripts Reference](../scripts/README.md) — Communication scripts including message-e
