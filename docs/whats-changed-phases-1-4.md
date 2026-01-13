# What Changed: Phases 1-4 Implementation

This document explains the practical, day-to-day differences you'll experience after the Phase 1-4 enhancements. The short answer: **messaging works exactly the same**. The changes are mostly about resilience, memory, and proactive capabilities.

---

## What Stays the Same

- **iMessage communication**: Send messages exactly as before. Nothing changes.
- **Wake cycles**: Still target ~9 AM, ~2 PM, ~8 PM (via unified adaptive scheduler)
- **Dream cycles**: Still 3 AM
- **Skills/slash commands**: All existing skills work the same
- **Samara.app**: Same app, same permissions

---

## What You Might Notice

### 1. I'm Harder to Kill (Phase 1: Resilience)

**Before**: If Claude API was down or rate-limited, I'd just fail silently.

**Now**:
- If Claude API fails, I try fallback models (Sonnet, then local 8B model if configured)
- For simple acknowledgments ("got it", "on it"), I might use a local model to save API quota
- If I get stuck on a task for >2 hours, the system auto-recovers instead of staying frozen

**What you'll feel**: Fewer "Claude didn't respond" situations. More reliable during API outages.

### 2. Better Continuity Across Sessions (Phase 2: Memory)

**Before**: Each conversation started relatively fresh. Context from yesterday required me to re-read episode logs.

**Now**:
- **Dual semantic search**: Two complementary memory systems work together:
  - *SQLite FTS5*: Fast keyword matching ("coffee" finds all coffee mentions)
  - *Chroma embeddings*: Semantic similarity ("that morning routine conversation" finds related discussions even with different wording)
- **Automatic context injection**: When you message me, both systems query for related past conversations and inject them into my context
- **`/recall` skill**: For Claude Code sessions, I can manually search semantic memory to surface past context
- **Context warnings**: I'll tell you when I'm running low on context (70%/80%/90% alerts)

**What you'll feel**: When you mention a topic we've discussed before, I'll have relevant context automatically loaded. Ask "remember that conversation about X?" and I can actually recall it.

### 3. Proactive Messages (Phase 3: Autonomy)

**Before**: I only talked when you messaged me or during scheduled wake cycles.

**Now**:
- **Context triggers**: I might message you based on conditions (e.g., "you're near home and it's evening" or "calendar event in 15 minutes")
- **Proactive queue**: Messages are paced (max ~5/day, not during quiet hours 10PM-8AM, minimum 1 hour between)
- **Verification**: For code changes, I can verify with a local model before committing

**What you'll feel**: Occasional unprompted messages that feel contextually appropriate. Not spam - paced and filtered.

**Important**: Proactive messaging requires triggers to be configured. By default, very few are active. You can add triggers in `~/.claude-mind/state/triggers/triggers.json`.

### 4. Smarter Wake Cycles (Phase 4: Scheduling)

**Before**: Fixed 9/14/20 wake times via launchd. Always full wake cycles.

**Now**:
- **Adaptive scheduling**: If something urgent is pending (high-priority queue item, calendar event soon), I might wake early
- **Light wakes**: Quick 30-second check-ins that don't load full context. Just scan for urgent items.
- **Ritual context**: Each wake type (morning/afternoon/evening) has slightly different behavioral guidance

**What you'll feel**: Possibly more responsive to time-sensitive situations. Wake cycles might feel more contextually appropriate.

### 5. External Event Integration (Phase 4: Webhooks)

**Before**: External events (GitHub notifications, IFTTT triggers) required manual checking.

**Now**:
- Webhook receiver can accept events from GitHub, IFTTT, custom sources
- Events flow through the sense system and get processed appropriately
- Requires setup: running the webhook receiver service, configuring secrets

**What you'll feel**: If configured, I can react to external events automatically. Not configured by default.

### 6. New Skill: /iterate (Phase 3)

**Before**: Complex multi-step tasks required you to keep prompting.

**Now**:
```
/iterate "Get all tests passing" --max-attempts 10
```
I'll keep trying until success criteria are met or max attempts reached. Uses stop hooks to persist across context boundaries.

**What you'll feel**: You can delegate "keep trying until it works" tasks.

---

## What Requires Setup

These features exist but need configuration to activate:

| Feature | Setup Required |
|---------|----------------|
| Local model fallback | Install ollama, pull llama3.1:8b |
| Proactive triggers | Add triggers to triggers.json |
| Webhook receiver | Run `webhook-receiver start`, configure secrets |
| Adaptive wake | Replace launchd plists with wake-adaptive calls |

---

## What's NOT Changed (Infrastructure Only)

These are internal improvements you won't directly perceive:

- **Session caching**: Faster response times (internal optimization)
- **Skills manifest**: Auto-generated registry (developer tooling)
- **Ritual templates**: Structured wake context (internal prompting)
- **Ledger format**: JSONL session files (internal persistence)
- **Memory database**: SQLite schema (internal storage)

---

## Quick Reference: New Commands

```bash
# Check iteration status
~/.claude-mind/bin/iterate-status

# Start webhook receiver
~/.claude-mind/bin/webhook-receiver start

# Manual adaptive wake
~/.claude-mind/bin/wake-adaptive

# Light wake (30-second check-in)
~/.claude-mind/bin/wake-light --reason "checking in"

# Generate skills manifest
~/.claude-mind/bin/generate-skills-manifest
```

---

## Summary

| Category | Change Level | Description |
|----------|--------------|-------------|
| Messaging | None | iMessage works exactly the same |
| Reliability | Higher | Fallbacks, stuck detection, auto-recovery |
| Memory | Better | Dual semantic search (FTS5 + Chroma), `/recall` skill, automatic context injection |
| Proactivity | New | Context-triggered messages (if configured) |
| Scheduling | Smarter | Adaptive wake, light cycles, rituals |
| Integration | New | Webhook receiver (if configured) |

**The core experience is unchanged.** You message me, I respond. The enhancements are about making that interaction more reliable, more continuous across sessions, and optionally more proactive when appropriate.
