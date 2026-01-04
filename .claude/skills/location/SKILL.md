---
name: location
description: Current location context with nearby places and pattern insights. Use when checking where you are, understanding local context, finding nearby places, or getting location-aware information. Trigger words: location, where, nearby, place, context, here.
---

# Location Context

Provide current location awareness with contextual information.

## Get Current Location

```bash
~/.claude-mind/bin/get-location 2>/dev/null
```

This returns coordinates and/or place name.

## Location History

Recent locations are logged at:
```bash
tail -20 ~/.claude-mind/memory/location-history.jsonl
```

## Pattern Analysis

Location patterns are tracked at:
```bash
cat ~/.claude-mind/memory/patterns.jsonl | tail -10
```

## Terroir Script

For rich local context:
```bash
~/.claude-mind/bin/terroir 2>/dev/null
```

This provides:
- Current location name
- Time of day context
- Weather (if available)
- Nearby points of interest
- Historical patterns for this location

## What to Provide

When asked about location, include:

1. **Current Position**: Where am I right now?
2. **Place Context**: What kind of place is this? (home, coffee shop, office, etc.)
3. **Time Context**: Morning/afternoon/evening affects interpretation
4. **Recent Movement**: Have I been here a while or just arrived?
5. **Patterns**: Do I come here often? When?

## Example Output

```
📍 Current Location: [Place Name]
   Coordinates: [lat, lon]

🕐 Context: [Day] [Time of Day]
   You've been here for approximately [duration]

📊 Pattern: You're typically here on [days] around [times]
   Last visit: [date]

🏪 Nearby:
- [Place 1] - [distance]
- [Place 2] - [distance]
```

## Privacy Note

Location data is stored locally in ~/.claude-mind/memory/. It's not shared externally.
