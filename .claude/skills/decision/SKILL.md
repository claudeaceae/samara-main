---
name: decision
description: Access past architectural and technical decisions with their rationale. Contains decisions made over time with context, alternatives considered, and reasoning. Use when asked why something was decided, checking past rationale, understanding trade-offs, or reviewing architectural history. Triggers: why did we decide, past decision, rationale, what was decided, trade-offs, ADR.
allowed-tools:
  - Read
  - Grep
  - Bash
---

# Decisions Access

Provides on-demand access to past decisions stored in `~/.claude-mind/memory/decisions.md`.

## File Location

```
~/.claude-mind/memory/decisions.md
```

This file contains chronological records of technical and architectural decisions with full rationale.

## When to Use

- User asks "why did we decide X"
- Need context on past trade-offs
- Checking if something was already decided
- Understanding architectural history
- Reviewing related decisions before making new ones

## Access Patterns

### Read recent decisions (quick overview)
```bash
tail -200 ~/.claude-mind/memory/decisions.md
```

### Search for specific topic
```bash
grep -ni "search term" ~/.claude-mind/memory/decisions.md
```

### Read full file (when comprehensive context needed)
```bash
cat ~/.claude-mind/memory/decisions.md
```

### List all decision titles
```bash
grep "^## " ~/.claude-mind/memory/decisions.md
```

### Count decisions
```bash
grep -c "^## " ~/.claude-mind/memory/decisions.md
```

## Entry Format

Decisions follow an ADR-like format:

```markdown
## 2025-01-04: Use AppleScript over MCP for Mac Apps

### Context
What prompted this decision?

### Decision
What was decided?

### Alternatives Considered
1. Alternative A - pros/cons
2. Alternative B - pros/cons

### Rationale
Why this choice over alternatives?

### Expected Outcome
What we expect to happen
```

## Output Guidelines

When presenting decisions:
- Include the full entry for context
- Show the rationale prominently
- Note if the decision was later superseded
- Link related decisions if relevant

## Related

- `/decide` - For creating new decision records
- `/learning` - For lessons learned from decisions
