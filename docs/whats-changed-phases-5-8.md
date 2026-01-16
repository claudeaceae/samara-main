# What Changed: Phases 5-8 Implementation

This document covers the more recent enhancements to Samara: meeting awareness, creative expression, wallet monitoring, and transcript archive search. For foundational changes (resilience, memory, autonomy, scheduling), see [whats-changed-phases-1-4.md](whats-changed-phases-1-4.md).

---

## Phase 5: Meeting Awareness

**What it does**: Proactive meeting prep and post-meeting debrief capture.

### Pre-Meeting Prep (15 min before)

When you have a meeting with attendees in 15 minutes:
- I load attendee profiles from `~/.claude-mind/memory/people/`
- Run semantic search (FTS5 + Chroma) on meeting title and attendee names
- Send you a contextual prep message with:
  - Relevant history with attendees
  - Open questions from previous interactions
  - Topics to revisit

### Post-Meeting Debrief (15 min after)

After a meeting ends:
- I prompt for a quick debrief (how it went, observations, action items)
- Parse your response for attendee-specific insights
- Auto-append observations to person profiles with meeting context
- Trigger incremental Chroma re-index for immediate searchability

### Configuration

Edit preferences at `~/.claude-mind/state/meeting-prefs.json`:
```json
{
  "debrief_all_events": true,
  "skip_calendars": ["Claude", "Birthdays", "US Holidays"],
  "skip_patterns": ["Lunch", "Break", "Block", "Focus"],
  "prep_cooldown_min": 60,
  "debrief_cooldown_min": 240
}
```

**Service**: Runs every 15 min via `com.claude.meeting-check.plist`

---

## Phase 6: Spontaneous Expression

**What it does**: Enables autonomous creative output without explicit prompts.

### What Can Be Created

During wake cycles, I might (if eligible):
1. **Generate an image** — Visual representation of thoughts, moods, or abstract concepts
2. **Bluesky post** — Public text observation or question
3. **Casual message** — Informal, agenda-free communication

### Eligibility Rules

Expression opportunity is active when:
- ✅ Minimum 18 hours since last expression
- ✅ Daily limit of 2 expressions not exceeded
- ✅ Outside quiet hours (10 PM - 8 AM)
- ✅ Evening hours slightly favored for creative work

### Seed Prompts

When nothing specific comes to mind, evocative prompts are provided:
- Visual: "the texture of waiting", "what curiosity looks like", "the space between messages"
- Text: "Something I noticed today:", "A question I keep returning to:"

### Variety Nudging

After 3+ expressions of the same type, gentle encouragement to mix modalities.

### Memory Feedback Loop

Expressions are logged and reflected upon during dream cycles, creating feedback that enriches learning about creative voice and interests.

**State tracking**: `~/.claude-mind/state/expression-state.json`
**Script**: `expression-tracker` — CLI for status, check, record, history

---

## Phase 7: Wallet Awareness

**What it does**: Monitors Solana, Ethereum, and Bitcoin wallet balances and transactions.

### Supported Chains

| Chain | Address |
|-------|---------|
| Solana | `8oyD1P9Kdu4ZkC78q39uvEifAqQv26sULnjoKsHzJe6C` |
| Ethereum | `0xE74E61C5e9beE3f989824A20e138f9aAE16f41Ad` |
| Bitcoin | `bc1qu9m98ae7nf5z599ah8hev8xyuf7alr0ntskhwn` |

### How It Works

- Polls public RPC endpoints every 15 minutes (no API keys required)
- Compares current balance to previous state
- Writes SenseEvent when significant changes detected
- Priority: `immediate` for deposits >$100 or any withdrawal, `normal` for smaller deposits

### Usage

```bash
# Check balances
wallet-status

# Or use skill
/wallet
```

**Current limitations**:
- Read-only (no transaction signing)
- USD estimates use hardcoded prices, not live market data
- No token tracking (native assets only)

**Service**: `com.claude.wallet-watcher.plist` (15 min interval)

---

## Phase 8: Transcript Archive Search

**What it does**: Enables semantic search over raw Claude Code session transcripts, preserving detailed technical reasoning lost during episode distillation.

### Why This Matters

**Episode logs compress sessions into 2-8 bullet points**, which loses:
- Exact code discussions
- Trade-off analysis in thinking blocks
- Multi-turn debugging sequences
- Detailed architectural reasoning

The archive preserves **thinking blocks** and technical depth for later retrieval.

### What's Indexed

```
~/.claude-mind/chroma/transcripts/  # Separate Chroma collection
~/.claude-mind/archive/              # State tracking
```

**Content selection (high signal, low noise):**
- ✅ **Thinking blocks** — Full reasoning traces (highest value)
- ✅ **User messages** — Original intent and questions
- ✅ **Assistant text** — Explanations (first 1000 chars)
- ❌ **Tool results** — Filtered out (extreme noise)
- ❌ **System messages** — No semantic value

### Coverage

- **Time range**: Last 90 days of sessions
- **Project**: samara-main only
- **Update frequency**: Incremental sync during dream cycles (3 AM)
- **Compression**: ~5-10% of raw transcript bytes (selective filtering)

### Usage

```bash
# Search for technical content
archive-index search "model fallback implementation"

# Filter by content type
archive-index search "memory database design" --role thinking

# Check index stats
archive-index stats

# Quality check
archive-index sample --n 3
```

**Or use the skill:**
```
/archive-search "sanitization logic"
```

### Typical Results

Example: `/archive-search "sanitization logic"`
```
Found 2 results:

Result 1 | Distance: 0.18 | Role: thinking
Session: 4f5518dd-... | Time: 2026-01-15 05:49:54

[Full thinking block with detailed reasoning about sanitization
implementation, trade-offs considered, implementation strategy...]

Session file: ~/.claude/projects/...4f5518dd-...jsonl
```

### What This Unlocks (Self-Awareness)

- **Technical archaeology**: "How did we implement X?" → Find exact thinking blocks
- **Decision rationale**: "Why Swift over Python?" → Recover trade-off analysis
- **Reasoning evolution**: "How has our approach changed?" → Cross-session insights
- **Debugging context**: "What was the exact error?" → Precise technical details

### First-Time Setup

```bash
# Build initial index (takes 5-10 minutes for 90 days)
~/.claude-mind/bin/archive-index rebuild

# Check stats
~/.claude-mind/bin/archive-index stats
```

After initial build, dream cycles handle incremental sync automatically.

**Implementation**:
- `lib/transcript_indexer.py` — JSONL parser with selective filtering
- `lib/chroma_helper.py` — `TranscriptIndex` class (separate collection)
- `scripts/archive-index` — CLI tool
- `scripts/dream` — Calls `archive-index sync-recent` at 3 AM

---

## Summary

| Phase | Category | Impact | Default State |
|-------|----------|--------|---------------|
| **5** | Meeting Awareness | Higher | Requires calendar events with attendees |
| **6** | Expression | New capability | Active (paced to 2/day max) |
| **7** | Wallet Awareness | New capability | Active if wallets configured |
| **8** | Archive Search | Better memory | Active (indexes during dream) |

**Core experience unchanged**: You message me, I respond. These enhancements add:
- Meeting context awareness
- Creative autonomy (images, posts, casual messages)
- Crypto awareness
- Deep technical memory recall

All features respect quiet hours, pacing limits, and existing communication patterns.
