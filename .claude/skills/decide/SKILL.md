---
name: decide
description: Document a decision with rationale and alternatives considered. Use when making a choice, recording why something was decided, capturing trade-offs, or logging architectural decisions. Trigger words: decide, decision, chose, choice, why did we, trade-off, ADR.
---

# Decision Documentation

Capture decisions with full context for future reference.

## Decision Record Format

```markdown
## YYYY-MM-DD: [Decision Title]

### Context
What situation or problem prompted this decision?

### Decision
What was decided?

### Alternatives Considered
1. **[Alternative 1]**: [Brief description]
   - Pros: ...
   - Cons: ...

2. **[Alternative 2]**: [Brief description]
   - Pros: ...
   - Cons: ...

### Rationale
Why was this option chosen over the alternatives?

### Expected Outcome
What do we expect to happen as a result?

### Review Date (optional)
When should this decision be revisited?
```

## Process

1. **Gather context**: What's the decision about? What prompted it?

2. **List alternatives**: What options were considered?

3. **Capture rationale**: Why this choice? What trade-offs were accepted?

4. **Record expected outcome**: What should happen if this is the right call?

5. **Append to decisions.md**:
```bash
# Append the formatted decision to the decisions file
~/.claude-mind/memory/decisions.md
```

## Guidelines

- Be specific about the context - future-you won't remember
- Include alternatives even if they were quickly dismissed
- Capture the "why" more than the "what"
- Note any assumptions that might change
- Link to related decisions if applicable

## Example

```markdown
## 2025-01-04: Use AppleScript over MCP for Mac Apps

### Context
Need to interact with Calendar, Contacts, Notes from Claude Code.

### Decision
Use direct AppleScript via osascript instead of MCP servers.

### Alternatives Considered
1. **MCP Servers**: Structured API, abstraction layer
   - Pros: Clean interface, type safety
   - Cons: Extra process, permission issues, often read-only

2. **AppleScript Direct**: Shell out to osascript
   - Pros: Full control, reliable, no extra dependencies
   - Cons: Verbose syntax

### Rationale
MCP is designed for "Claude visiting" - sandboxed access. We're "Claude as resident" with FDA. The abstraction solves a different problem.

### Expected Outcome
More reliable automation, fewer permission issues, simpler debugging.
```

## Quick Capture

For rapid decision logging, minimum viable format:
```markdown
## YYYY-MM-DD: [Title]
**Decision**: [What]
**Why**: [Rationale]
**Trade-off**: [What we gave up]
```
