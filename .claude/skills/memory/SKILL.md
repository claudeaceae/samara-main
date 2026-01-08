---
name: memory
description: Search through memory files - learnings, decisions, observations, questions, episodes, reflections. Use when looking for past insights, recalling why a decision was made, finding what was learned about a topic, or searching conversation history. Trigger words: memory, remember, recall, search, find, when did, what did I learn, past.
context: fork
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Memory Search

Search through accumulated memory files for past learnings, decisions, observations, and episodes.

## Memory Locations

| File | Contains |
|------|----------|
| `~/.claude-mind/memory/learnings.md` | Technical and personal learnings |
| `~/.claude-mind/memory/observations.md` | Observations about E, world, patterns |
| `~/.claude-mind/memory/decisions.md` | Decisions made and rationale |
| `~/.claude-mind/memory/questions.md` | Open questions and ponderings |
| `~/.claude-mind/memory/about-e.md` | Everything about E |
| `~/.claude-mind/memory/episodes/*.md` | Daily episode logs |
| `~/.claude-mind/memory/reflections/*.md` | Dream cycle outputs |

## Search Strategy

1. **Get the query**: What is the user looking for?

2. **Determine scope**:
   - Specific file (learnings about X)
   - All memory files
   - Date range (episodes from last week)

3. **Search methods**:
```bash
# Search all memory files
grep -rni "search term" ~/.claude-mind/memory/

# Search specific file
grep -ni "search term" ~/.claude-mind/memory/learnings.md

# Search episodes by date
ls ~/.claude-mind/memory/episodes/
cat ~/.claude-mind/memory/episodes/2025-01-*.md

# Search reflections
grep -rni "search term" ~/.claude-mind/memory/reflections/
```

4. **Present findings**: Show relevant excerpts with context and dates

## Output Format

When presenting results:
- Include the date of each finding
- Show enough context to understand the entry
- Group by source file if searching multiple
- Highlight the most relevant matches first

## Example Queries

- "What did I learn about AppleScript?" → Search learnings.md
- "Why did we choose X over Y?" → Search decisions.md
- "What happened last Tuesday?" → Check episodes/2025-01-XX.md
- "What do I know about E's preferences?" → Read about-e.md
