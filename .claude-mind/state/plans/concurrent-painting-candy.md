# Plan: Comprehensive Hot Digest Format Improvement

## Problem Statement

The hot digest produces truncated, hard-to-parse fragments like:
```
É: Yeah yeah it might be a good idea to research this and check if there's a means of even securing a m
```

**Root causes identified:**
1. `summarize_with_ollama()` only uses first 200 chars of content (line 104)
2. Multiple messages concatenated with semicolons/pipes (lines 196, 200)
3. No parsing of the dialogue structure stored in `content` field
4. All surfaces treated identically despite different use cases
5. No priority-based token budgeting

## Data Available

Events store rich data that's being underutilized:

```json
{
  "surface": "imessage",
  "summary": "É: Yeah yeah it might be...",  // Truncated at ~100 chars
  "content": "**É:** Full message here...\n\n**Claude:** Full response...",  // Up to 2000 chars!
  "metadata": {"emotional_texture": "...", "open_threads": [...]}
}
```

The `content` field contains BOTH user message AND Claude's response in `**Speaker:** message` format.

## Solution Overview

1. **Surface categorization** - Different formatting for different surface types
2. **Dialogue parsing** - Extract and display actual conversations from `content`
3. **Priority-based token budget** - Conversations get 50%, activities 35%, sense 15%
4. **Use more content** - 500 chars instead of 200 for Ollama input

## Implementation

### File to Modify
`lib/hot_digest_builder.py` (264 lines → ~400 lines)

### Changes

#### 1. Add Surface Categories (new constants at top)

```python
import re

CONVERSATIONAL_SURFACES = {"imessage", "x", "bluesky", "email"}
ACTIVITY_SURFACES = {"cli", "wake", "dream"}
SENSE_SURFACES = {"webhook", "location", "calendar", "sense", "system"}

TOKEN_WEIGHTS = {
    "conversational": 0.50,
    "activity": 0.35,
    "sense": 0.15,
}
```

#### 2. Add Dialogue Parser (new function)

```python
def parse_dialogue(content: str) -> list[tuple[str, str]]:
    """Parse **Speaker:** message format into (speaker, message) tuples."""
    if not content:
        return []
    pattern = r'\*\*([^*]+):\*\*\s*(.*?)(?=\*\*[^*]+:\*\*|$)'
    matches = re.findall(pattern, content, re.DOTALL)
    return [(speaker.strip(), message.strip()) for speaker, message in matches]
```

#### 3. Add Surface-Specific Formatters (new functions)

```python
def format_conversational_event(event: dict, max_chars: int = 500) -> str:
    """Format iMessage/X events as dialogue."""
    content = event.get("content", "")
    dialogue = parse_dialogue(content)

    if not dialogue:
        return event.get("summary", "")[:max_chars]

    lines = []
    remaining = max_chars
    for speaker, message in dialogue:
        if speaker.startswith("Sense:"):
            speaker = f"[{speaker}]"
        msg_text = message[:remaining - len(speaker) - 5] + "..." if len(message) > remaining else message
        lines.append(f"{speaker}: {msg_text}")
        remaining -= len(lines[-1])
        if remaining < 50:
            break

    return "\n".join(lines)


def format_activity_event(event: dict, max_chars: int = 300) -> str:
    """Format CLI/wake events as activity summaries."""
    content = event.get("content", "") or event.get("summary", "")
    lines = content.split("\n")
    result = []
    total = 0
    for line in lines:
        if total + len(line) > max_chars:
            break
        result.append(line)
        total += len(line) + 1
    return "\n".join(result) if result else content[:max_chars]


def format_sense_event(event: dict) -> str:
    """Format sense events as compact one-liners."""
    surface = event.get("surface", "sense")
    summary = event.get("summary", "")
    if summary.startswith("Sense:"):
        parts = summary.split(":", 2)
        if len(parts) >= 3:
            summary = parts[2].strip()
    return f"[{surface.capitalize()}] {summary[:100]}"
```

#### 4. Replace `build_digest()` with Priority-Based Version

- Categorize events into conversational/activity/sense buckets
- Calculate token budget per category
- Build sections with surface-appropriate formatting
- Format conversational events as dialogue, not concatenated fragments

#### 5. Update `summarize_with_ollama()` to Use More Content

Change line 104:
```python
# Before:
text += f"\n  Detail: {content[:200]}"

# After:
text += f"\n  Detail: {content[:500]}"
```

## Expected Output

**Before:**
```
### 1h ago [Imessage]
É: Yeah yeah it might be a good idea to research this and check if there's a means of even securing a m; É: I wonder if there are any sound ways we could generate income passively
```

**After:**
```
### Conversations

**1h ago [iMessage]**
É: Yeah yeah it might be a good idea to research this and check if there's a means of even securing a means of earning at least 200/mo off passive income/staking - you'd basically have perpetual life with that small an amount
Claude: That's a compelling framing. $200/month is about $2400/year. At 6-8% APY, I'd need roughly $30-40k staked to hit that. I've got over 3x that in SOL alone right now...

### Sessions

**25m ago**: Deep dive into Samara's message routing architecture - explored MessageWatcher, SessionManager, ClaudeInvoker flow.

### System Events

- 1h ago: [Sense] Wallet deposit notification - 46.27 SOL (~$6,940)
```

## Verification

1. **Test without Ollama:**
   ```bash
   ~/.claude-mind/bin/build-hot-digest --hours 12 --no-ollama
   ```
   Verify:
   - iMessage shows as dialogue with É and Claude turns
   - CLI shows as activity summaries (not truncated mid-word)
   - Sense events are compact one-liners
   - Output < 3000 tokens

2. **Test with Ollama:**
   ```bash
   ~/.claude-mind/bin/build-hot-digest --hours 12
   ```
   Verify summarization still works for large batches

3. **Integration test:**
   - Start new CLI session
   - Context should have readable conversation history
   - iMessage content should be parseable without tool calls

## Backward Compatibility

- No changes to `events.jsonl` format
- No changes to callers (`hydrate-session.sh`, `MemoryContext.swift`)
- No changes to `EpisodeLogger.swift`
- CLI `--format json` structure unchanged

## Risks

| Risk | Mitigation |
|------|------------|
| Dialogue parsing fails on edge cases | Fallback to summary if no matches |
| Token budget exceeded | Hard cap on section sizes, same as before |
| Breaking existing consumers | Output is still markdown, just better formatted |
