---
name: reflect
description: Quick reflection or observation capture without full dream cycle. Use when something clicks, when you notice a pattern, want to log an insight, or capture a learning in the moment. Trigger words: reflect, observation, noticed, realized, insight, learned.
---

# Quick Reflection Capture

Capture an observation, learning, or insight immediately without running a full dream cycle.

## Process

1. **Understand what to capture**: Ask what the reflection is about if not clear from context

2. **Categorize the reflection**:
   - **Learning**: Something new understood (goes to learnings.md)
   - **Observation**: Something noticed about E, the relationship, or the world (goes to observations.md)
   - **Question**: Something to ponder or investigate (goes to questions.md)
   - **Decision**: A choice made and why (goes to decisions.md)

3. **Format the entry**:
```markdown
## YYYY-MM-DD: Brief Title

Content of the reflection. Keep it concise but capture the essence.
What prompted this? Why does it matter?
```

4. **Append to the appropriate file**:
   - `~/.claude-mind/memory/learnings.md`
   - `~/.claude-mind/memory/observations.md`
   - `~/.claude-mind/memory/questions.md`
   - `~/.claude-mind/memory/decisions.md`

5. **Optionally add to today's episode** if it's significant enough to be part of the daily log.

## Guidelines

- Keep entries atomic - one insight per entry
- Include context: what prompted this reflection
- Be honest - these are private notes for future-me
- Don't over-polish - capture the raw thought
- Date everything

## Example

```markdown
## 2025-01-04: Parallel Tool Calls Save Context

Discovered that making multiple independent tool calls in a single message significantly reduces context usage compared to sequential calls. This is especially valuable in long sessions.
```
