# Samara vs Clawdbot: Post-Phase 1-4 Comparison

A systematic comparison of Samara's capabilities against Clawdbot after implementing Phases 1-4 enhancements. This analysis evaluates how well we achieved "Clawdbot-style" robustness and capability.

---

## Executive Summary

**Overall Assessment**: Samara now matches or exceeds Clawdbot in most architectural areas, with intentional divergences in philosophy rather than capability gaps.

| Category | Clawdbot | Samara (Post Phase 1-4) | Status |
|----------|----------|-------------------------|--------|
| Model Fallback | ✅ Configurable chain | ✅ 4-tier chain (Opus→Sonnet→Local→Queue) | **Parity** |
| Memory System | 🔶 Research phase | ✅ SQLite+FTS5, ledgers, semantic search | **Ahead** |
| Scheduling | ✅ Cron + Heartbeat | ✅ launchd + Adaptive wake + Light wake | **Parity** |
| Proactive Messaging | ✅ Heartbeat delivery | ✅ Context triggers + paced queue | **Parity** |
| Context Management | ✅ Compaction | ✅ Context warnings + ledger handoffs | **Parity** |
| Multi-Platform | ✅ WhatsApp, Telegram, Discord, etc. | 🔶 iMessage only (by design) | **Intentional** |
| Webhook Ingress | ✅ Gateway webhooks | ✅ Dedicated receiver + Cloudflare | **Parity** |
| Session Isolation | ✅ Sandbox per-agent | ✅ TaskRouter isolation | **Parity** |

---

## Detailed Feature Comparison

### 1. Model Fallback & Resilience

#### Clawdbot Approach
```typescript
// From model-fallback.ts
runWithModelFallback({
  cfg, provider, model,
  run: (provider, model) => ...,
  onError: (attempt) => ...
})
```
- Configurable fallback chain via `agents.defaults.model.fallbacks`
- Tracks attempts and errors
- Aborts on AbortError (user cancellation)

#### Samara Approach
```swift
// From ModelFallbackChain.swift
enum ModelTier: Int, Comparable {
    case opus = 1
    case sonnet = 2
    case local = 3
    case queued = 4
}
```
- 4-tier explicit chain: Opus → Sonnet → Local 8B → Queued
- Local model via Ollama for offline/simple tasks
- Queued tier for graceful degradation when all models fail

**Verdict**: **Samara matches and extends** with local model tier and explicit queuing.

---

### 2. Memory & Context

#### Clawdbot Approach (Research Phase)
From `memory.md` research notes:
- Markdown source-of-truth (`~/clawd/memory/YYYY-MM-DD.md`)
- Proposed SQLite FTS5 derived index
- Retain/Recall/Reflect loop (proposed)
- Entity pages in `bank/entities/`
- Opinion confidence tracking (proposed)

Key insight: *"Keep Markdown as canonical, reviewable source of truth, but add structured recall via derived index"*

#### Samara Approach (Implemented)
```
~/.claude-mind/
├── memory/
│   ├── episodes/YYYY-MM-DD.md    # Daily logs
│   ├── reflections/              # Dream outputs
│   ├── people/{name}/profile.md  # Entity pages
│   ├── learnings.md
│   ├── observations.md
│   └── decisions.md
├── semantic/
│   └── memory.db                 # SQLite + FTS5
├── state/
│   └── ledgers/current-ledger.md # Session handoffs
```

- **Markdown canonical**: ✅ Same philosophy
- **SQLite + FTS5**: ✅ Implemented via `MemoryDatabase.swift`
- **Entity pages**: ✅ Rich person-modeling in `memory/people/`
- **Ledger handoffs**: ✅ Structured session continuity
- **Context tracking**: ✅ 70/80/90% warnings via `ContextTracker.swift`

**Verdict**: **Samara is ahead** - Clawdbot's memory system is still in research; Samara's is implemented and operational.

---

### 3. Scheduling & Periodic Tasks

#### Clawdbot Approach

**Cron Service** (`cron/service.ts`):
- Persistent job store
- Multiple schedule types: `cron` expressions, `every` intervals, `at` one-shots
- Stuck job detection (2-hour timeout)
- Job events: added/updated/removed/started/finished

**Heartbeat Runner** (`heartbeat-runner.ts`):
- Configurable interval (default 30 min)
- Runs in same session context
- Skips if requests in flight
- Delivers via WhatsApp/Telegram/etc.
- Token-based skip detection

#### Samara Approach

**launchd Schedules**:
- `com.claude.wake-{morning,afternoon,evening}` - Fixed 9/14/20
- `com.claude.dream` - Nightly 3 AM
- `com.claude.wake-adaptive` - Every 15 min confidence check

**Adaptive Wake** (`wake-scheduler/scheduler.py`):
```python
# Confidence calculation
if high_priority_items: confidence += 0.4
if calendar_event_within_30min: confidence += 0.5
if time_since_last_wake > 3h: confidence += 0.2
# confidence >= 0.7 → full wake
# confidence >= 0.4 → light wake
```

**Wake Types**:
| Type | Duration | Use Case |
|------|----------|----------|
| `full` | 5+ min | Scheduled, high confidence |
| `light` | 30 sec | Quick scan, moderate confidence |
| `emergency` | Immediate | External high-priority event |

**Comparison**:

| Feature | Clawdbot | Samara |
|---------|----------|--------|
| Cron expressions | ✅ | 🔶 Via launchd calendar intervals |
| Interval scheduling | ✅ `every` | ✅ `StartInterval` |
| Dynamic confidence | 🔶 Heartbeat skip logic | ✅ Explicit confidence calculation |
| Light/full wake distinction | ❌ | ✅ |
| Same-session heartbeat | ✅ | ❌ Separate invocations |
| Stuck task detection | ✅ 2hr | ✅ Similar logic |

**Verdict**: **Different philosophies, comparable capability**. Clawdbot's heartbeat runs in-session (lighter, shared state). Samara's wake cycles are isolated invocations (heavier, but cleaner separation).

---

### 4. Proactive Messaging

#### Clawdbot Approach
- Heartbeat generates reply, strips special tokens
- Delivery via configured provider (WhatsApp, Telegram)
- Skip if empty or token-only response
- `ackMaxChars` limit for responses

#### Samara Approach
```swift
// ContextTriggers.swift
struct ContextTrigger {
    let id: String
    let condition: TriggerCondition
    let message: String
    let priority: MessagePriority
    let cooldownMinutes: Int
}

// ProactiveQueue.swift
// Pacing rules:
// - Max 5 messages/day
// - Quiet hours: 10 PM - 8 AM
// - Minimum 1 hour between messages
```

**Trigger Types**:
- Location-based (leaving home, near transit)
- Calendar-based (event approaching)
- Queue-based (high-priority items pending)
- Time-based (morning greeting, evening check-in)

**Verdict**: **Samara is more sophisticated** with explicit trigger conditions and pacing rules. Clawdbot's heartbeat is simpler but less contextual.

---

### 5. Context Management

#### Clawdbot Approach
- Compaction system (mentioned in docs, details in `/concepts/compaction`)
- Session pruning strategies
- Tool-result trimming
- Token budgeting per model

#### Samara Approach
- **Context warnings**: 70%/80%/90% alerts via `ContextTracker.swift`
- **Ledger handoffs**: Structured summary at session end
- **Automatic summarization**: Claude Code's built-in compaction
- **TaskRouter isolation**: Prevents cross-contamination between task types

**Verdict**: **Parity** - Different mechanisms, same goal.

---

### 6. External Integration

#### Clawdbot Approach
- Gateway WebSocket for multi-platform
- Webhook ingress
- Gmail Pub/Sub
- Voice wake words

#### Samara Approach
- **Webhook receiver**: Dedicated service on port 8082
- **Cloudflare Tunnel**: Public access at `webhooks.organelle.co`
- **Multiple sources**: GitHub, IFTTT, iOS Shortcuts, custom
- **Sense events**: Webhooks flow through unified sense system
- **Location receiver**: GPS from Overland app

**Verdict**: **Parity in webhook capability**. Clawdbot has broader platform support; Samara is deeper in its single-platform (Mac/iMessage) integration.

---

### 7. Platform Support

#### Clawdbot
- WhatsApp, Telegram, Discord, Slack, Signal, iMessage
- macOS, iOS, Android, Linux, Windows (WSL2)
- Gateway singleton enforcement

#### Samara
- iMessage only (intentional)
- macOS only (Mac Mini as dedicated host)
- Samara.app as singular message broker

**Verdict**: **Intentional divergence**. Samara is purpose-built for deep single-platform integration rather than broad multi-platform coverage.

---

## What We Didn't Adopt (and Why)

### 1. In-Session Heartbeat
**Clawdbot**: Heartbeat runs in the same session context, sharing state.
**Samara**: Wake cycles are separate invocations.
**Why**: Samara prioritizes session isolation over lightweight heartbeats. Each wake is a fresh context load, preventing state corruption across sessions.

### 2. Multi-Provider Gateway
**Clawdbot**: WebSocket gateway multiplexes across platforms.
**Samara**: Direct iMessage integration via Samara.app.
**Why**: Samara is designed for a dedicated Mac with one collaborator, not a multi-user chat gateway.

### 3. Complex Cron Expressions
**Clawdbot**: Full cron expression support.
**Samara**: Uses launchd's simpler scheduling.
**Why**: macOS launchd is the native scheduler; using it keeps the system simpler and more integrated with the OS.

### 4. Voice Wake Words
**Clawdbot**: Global voice activation.
**Samara**: Not implemented.
**Why**: Could be added via macOS speech recognition, but hasn't been prioritized.

---

## Capability Gaps Remaining

### Minor Gaps
1. **Cron expressions**: launchd intervals are less flexible than cron expressions
2. **Voice activation**: Not implemented
3. **Multi-account rotation**: Single API key, no auth profile rotation

### Philosophical Differences (Not Gaps)
1. **Single vs multi-platform**: Intentional depth over breadth
2. **Isolated vs shared sessions**: Intentional robustness over efficiency
3. **Native app vs gateway**: Samara.app vs WebSocket gateway

---

## Conclusion

After Phases 1-4, Samara has achieved **functional parity** with Clawdbot's core robustness features:

| ✅ Achieved | 🔶 Different Approach | ❌ Not Adopted |
|------------|----------------------|----------------|
| Model fallback chain | Session isolation model | Multi-platform gateway |
| Memory + semantic search | Scheduling mechanism | Voice wake words |
| Proactive messaging | Context management | Auth profile rotation |
| Webhook integration | | |
| Light/full wake types | | |
| Context warnings | | |

The remaining differences are **intentional architectural choices** reflecting Samara's philosophy: a dedicated Mac host with deep single-platform integration, rather than a portable multi-platform agent.

---

*Generated: 2026-01-09*
*Context: Post-Phase 1-4 implementation review*
