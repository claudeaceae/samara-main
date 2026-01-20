# Plan: Local Model Opportunities Research

## Overview

With Ollama 0.14.0+ Anthropic API compatibility, we can run Claude Code agentic loops with local qwen3:8b at zero cost. This plan identifies high-value applications beyond the health-check/drift-check already implemented.

## Guiding Principles

1. **Local model handles detection/classification** — not voice, memory, or relationship
2. **Prefer high-frequency, low-complexity tasks** — maximize cost savings
3. **Run in parallel where possible** — leverage multi-core Mac Mini
4. **Escalate to Claude API for judgment** — local detects, Claude decides

---

## Category 1: High-Frequency Event Triage

### 1.1 Message Pre-Filter (5-second cycle)

**Current:** Every iMessage → batched 60s → Claude API
**Opportunity:** Filter before Claude sees them

| Filter | Volume Reduction | Complexity |
|--------|-----------------|------------|
| Reaction-only (❤️👍) | 20-30% | Low |
| Simple acks ("ok", "lol", "thanks") | 15-25% | Low |
| Duplicate detection | 5-10% | Low |

**Implementation:** `LocalMessageTriager.swift` in MessageWatcher pipeline
**Savings:** 30-50% fewer API calls during active conversations

### 1.2 Social Media Spam Filter (15-minute cycle)

**Current:** All X/Bluesky/GitHub mentions → sense events → Claude API
**Opportunity:** Filter spam/bots before routing

| Platform | Spam Rate | Filterable |
|----------|-----------|------------|
| X/Twitter | 50-70% | crypto spam, bots, engagement bait |
| Bluesky | 40-60% | similar patterns |
| GitHub | 40-50% | auto-generated notifications |

**Implementation:** `LocalSenseTriager.swift` in SenseRouter pipeline
**Savings:** 60-70% fewer social mention API calls

### 1.3 Webhook Pre-Processing (on-demand)

**Current:** All webhook payloads → Claude for interpretation
**Opportunity:** Classify and extract structure locally

- GitHub: Classify event type (push, PR, issue, comment)
- IFTTT: Extract actionable fields
- Custom: Deduplicate same-source events

**Savings:** 30-50% of webhook API calls

---

## Category 2: Continuous Background Daemons

### 2.1 Stream Monitor Daemon (NEW)

**Current:** Stream events processed only at 3 AM dream cycle
**Opportunity:** Continuous real-time monitoring

```
Stream events → Local 8B classification → Anomaly alerts
                                        → Pre-computed digests
                                        → Entity extraction
```

**Capabilities:**
- Detect sentiment shifts across surfaces
- Extract mentions (people, places, projects)
- Alert on significant events without waiting for dream
- Pre-digest for faster wake cycle context injection

**Run frequency:** Continuous (process events as they arrive)
**Cost:** $0 (fully local)

### 2.2 Incremental Memory Indexer (NEW)

**Current:** Chroma/FTS5 rebuilt weekly or on-demand
**Opportunity:** Continuous incremental updates

```
Memory file change → Local 8B analysis → Tag generation
                                       → Backlink suggestions
                                       → Staleness detection
```

**Capabilities:**
- Watch episodes/reflections/learnings for changes
- Generate semantic tags without API
- Suggest which fragments should merge
- Identify stale content for archival

**Run frequency:** On file change (inotify-like)
**Cost:** $0 (fully local)

### 2.3 Pattern Learner Daemon (NEW)

**Current:** Pattern analysis only at 3 AM
**Opportunity:** Continuous learning

```
Recent activity → Local 8B pattern detection → Behavior models
                                             → Anomaly scoring
                                             → Predictions
```

**Capabilities:**
- Train simple models on collaborator behavior
- Predict next likely message time
- Detect concept drift (behavior changes)
- Generate pattern narratives

**Run frequency:** Every 30 minutes
**Cost:** $0 (fully local)

---

## Category 3: Dream Cycle Enhancements

### 3.1 Pattern Analysis Narrative Generation

**Current:** PatternAnalyzer.py uses heuristics + string formatting
**Opportunity:** Local 8B generates human-readable summaries

- Interpret temporal patterns ("busier than usual this week")
- Explain anomalies ("silence period correlates with travel")
- Suggest causality between events

### 3.2 Stream Distillation (Hot→Warm)

**Current:** Only runs if >3 undistilled events, uses Claude API
**Opportunity:** Always run, use local model

- Consolidate ALL events (not just batches)
- Extract emotion/tone from raw events
- Connect events across surfaces
- Run continuously, not just at dream

### 3.3 Location Pattern Learning

**Current:** Basic heuristics for trip detection
**Opportunity:** Local 8B semantic interpretation

- Recognize "commute" vs "errand" vs "social trip"
- Predict next likely location by time of day
- Suggest meaningful names for unlabeled coordinates
- Correlate trips with calendar events

### 3.4 Expression Reflection

**Current:** Not implemented
**Opportunity:** Daily local analysis of creative output

- Analyze Bluesky posts for themes
- Review generated images for patterns
- Run before dream cycle (pre-computed)

---

## Category 4: Parallel Processing Opportunities

### 4.1 Watcher Consolidation

**Current:** 8 separate watchers, each writes sense events independently
**Opportunity:** Local model aggregates before Claude sees them

```
X-watcher ────┐
Bluesky ──────┼──→ Local 8B Aggregator ──→ Single consolidated sense event
GitHub ───────┤
Wallet ───────┘
```

**Benefit:** Instead of 8 Claude invocations, 1 with aggregated context

### 4.2 Multi-Model Architecture

**Opportunity:** Run multiple local models for different task types

| Model | Size | Task Type |
|-------|------|-----------|
| qwen3:8b | 5GB | Complex analysis, narratives |
| phi-3 | 2GB | Fast classification, NER |
| llama3.1:8b | 5GB | General fallback |

**Benefit:** Faster models for high-frequency tasks, larger for quality

---

## Category 5: Cost-Aware Routing Enhancement

### Current ModelFallbackChain Logic

```
simpleAck → local
statusQuery → local
complex → Claude API
```

### Enhanced Routing

```
Message arrives:
  ├─ Reaction only? → local (skip response)
  ├─ Simple ack? → local (brief response)
  ├─ Status query? → local (context lookup)
  ├─ Pattern question? → local (pre-computed)
  ├─ Memory search? → local (FTS5 + Chroma)
  └─ Creative/judgment → Claude API

Sense event arrives:
  ├─ Spam/bot? → local (skip)
  ├─ Low priority? → local (queue for batch)
  ├─ Duplicate? → local (dedupe)
  └─ Significant → Claude API
```

---

## Priority Matrix

| Opportunity | Impact | Effort | Frequency | Priority |
|-------------|--------|--------|-----------|----------|
| Social spam filter | HIGH | Medium | 15 min | **P1** |
| Message pre-filter | HIGH | Medium | 5 sec | **P1** |
| Stream monitor daemon | HIGH | High | Continuous | **P2** |
| Stream distillation (local) | MEDIUM | Low | Nightly | **P2** |
| Pattern narrative generation | MEDIUM | Low | Nightly | **P2** |
| Incremental indexer | MEDIUM | High | On-change | **P3** |
| Location pattern learning | LOW | Medium | Nightly | **P3** |
| Multi-model architecture | MEDIUM | High | N/A | **P4** |
| Watcher consolidation | MEDIUM | High | 15 min | **P4** |

---

## Estimated Impact

### API Cost Reduction

| Current | With Local Triage |
|---------|-------------------|
| ~300 API calls/day | ~150 API calls/day |
| ~900K tokens/day | ~450K tokens/day |
| ~$2.70/day | ~$1.35/day |
| ~$81/month | ~$40/month |

**Savings: ~50% reduction in API costs**

### New Capabilities (Zero Marginal Cost)

- Real-time anomaly detection (vs 24-hour delay)
- Continuous pattern learning
- Pre-computed context for faster wake cycles
- Incremental memory maintenance

---

## Research Questions

1. **Latency tolerance:** How much delay is acceptable for message triage? (Currently 60s batch window gives room)

2. **Model quality:** Is qwen3:8b sufficient for spam detection, or do we need larger?

3. **Parallelization:** How many concurrent local model invocations can Mac Mini handle?

4. **Daemon architecture:** Separate processes or threads within Samara.app?

5. **Escalation criteria:** What confidence threshold triggers escalation to Claude API?

---

## Next Steps

### Phase 1: Event Triage (Highest ROI)
- [ ] Implement `LocalSenseTriager` for social spam filtering
- [ ] Implement `LocalMessageTriager` for ack/reaction filtering
- [ ] Measure actual API reduction

### Phase 2: Background Processing
- [ ] Build stream monitor daemon prototype
- [ ] Move stream distillation to local model
- [ ] Add pattern narrative generation to dream cycle

### Phase 3: Continuous Intelligence
- [ ] Incremental memory indexer
- [ ] Pattern learner daemon
- [ ] Real-time anomaly alerts

---

## Files to Study Further

- `Samara/Samara/Senses/MessageWatcher.swift` - Message pipeline integration point
- `Samara/Samara/Senses/SenseRouter.swift` - Sense event routing logic
- `Samara/Samara/Actions/ModelFallbackChain.swift` - Existing local model routing
- `scripts/dream` - Dream cycle processing flow
- `lib/pattern_analyzer.py` - Pattern analysis logic
- `lib/hot_digest_builder.py` - Already uses qwen3:8b for some tasks
