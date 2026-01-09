---
name: note
description: Quick observation capture about a person. Use when noticing something about someone, wanting to record a detail, or capturing context from a conversation. Trigger words: note about, noticed, observation about, remember that, jot down.
---

# Quick Person Note

Append an observation to a person's profile without breaking flow.

## Process

1. **Parse the input**: Extract person name and observation
   - `/note lucy plays aggressive chess` → name: "lucy", note: "plays aggressive chess"
   - `/note about e prefers morning conversations` → name: "e", note: "prefers morning conversations"

2. **Check if person exists**:
   ```bash
   ls ~/.claude-mind/memory/people/{name}/profile.md
   ```

3. **If person doesn't exist**: Ask whether to create them first
   - Don't silently create - confirm intent
   - Then use `/person {name}` flow to create

4. **Format the note**:
   ```markdown

   ## YYYY-MM-DD: Brief Title

   The observation itself. Keep it concise but capture the texture.
   Context: what prompted this if relevant.
   ```

5. **Append to profile**: Use Edit tool to append the formatted note to the end of their profile.md

6. **Confirm**: Brief acknowledgment that the note was captured

## Guidelines

- **Atomic observations**: One insight per note
- **Include context**: What prompted noticing this?
- **Use today's date**: Format as YYYY-MM-DD
- **Brief titles**: 3-5 words summarizing the observation
- **Texture over data**: "Plays aggressive sacrificial chess" > "Chess skill: advanced"

## Examples

**Quick capture:**
```
/note lucy prefers direct communication
```
→ Appends dated observation to Lucy's profile

**With context:**
```
/note e mentioned frustration with verbose AI responses today
```
→ Captures both the observation and the context

**Natural trigger:**
```
"I noticed Cal gets energized by debugging sessions"
```
→ Prompts to capture as note about Cal
