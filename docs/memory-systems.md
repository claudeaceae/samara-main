# Memory Systems

Deep documentation of Samara's memory architecture, from curated files to searchable indexes.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Overview

Samara maintains multiple complementary memory systems:

| System | Purpose | Technology |
|--------|---------|------------|
| Episode logs | Daily narrative summaries | Markdown files |
| Unified event stream (contiguous memory) | Cross-surface continuity and audit trail | JSONL append-only stream |
| Learnings/Observations | Curated insights | Markdown files |
| SQLite FTS5 | Keyword search | Swift native |
| Chroma | Semantic search | Python + embeddings |
| Transcript Archive | Raw session archaeology | Chroma (separate collection) |

---

## 4-Domain Architecture (Strictly Enforced)

The runtime (`~/.claude-mind/`) is organized into exactly **4 domains**:

| Domain | Purpose | Contains |
|--------|---------|----------|
| **self/** | WHO I AM | identity.md, goals.md, credentials/, avatar images |
| **memory/** | WHAT I KNOW | episodes/, stream/, people/, learnings.md, chroma/ |
| **state/** | WHAT'S HAPPENING | projects.md, plans/, services/, location.json |
| **system/** | HOW IT RUNS | config.json, bin/, lib/, logs/, instructions/ |

**Root level only contains:**
- `.claude/` → symlink to repo hooks/skills/agents
- `.venv/` — Python virtual environment
- `CLAUDE.md` → symlink to repo
- The 4 domain directories

**Enforcement:** Nothing else belongs at root. If you're tempted to create a file or directory at `~/.claude-mind/something`, it belongs in one of the 4 domains:
- Config? → `system/`
- Scripts/libs? → `system/`
- Logs? → `system/logs/`
- Memory/knowledge? → `memory/`
- Runtime state? → `state/`
- Identity/goals? → `self/`

See the [Full Directory Structure](#appendix-full-directory-structure) appendix for complete layout.

---

## Contiguous Memory (Unified Stream)

Samara writes every interaction and sense event into daily shard files at
`~/.claude-mind/memory/stream/daily/events-YYYY-MM-DD.jsonl`, with a sidecar distilled index
at `~/.claude-mind/memory/stream/distilled-index.jsonl`. This stream powers the hot digest
used for session hydration and provides an auditable timeline across iMessage, CLI,
wake/dream, and satellite services.

Key touchpoints:
- Samara app dual-writes to the stream via `EpisodeLogger.swift`
- Claude Code sessions write stream events at SessionEnd
- Wake and dream cycles emit system events
- Dream cycle distills the stream into episode logs and marks events as distilled

Full design, schema, and extension guidance:
`~/.claude-mind/state/plans/contiguous-memory-system.md`

## Claude Code Session Retention

Claude Code maintains complete session transcripts in `~/.claude/projects/`, organized by working directory. This is separate from Samara's curated memory files.

**Retention policy:**
- Configured via `cleanupPeriodDays` setting in `.claude/settings.json`
- **Current setting: 36,500 days (~100 years)** - effectively permanent retention
- **Automatically configured during `birth.sh` setup** - new organisms get this by default
- Default (if unset): ~30 days auto-cleanup
- Session files lost to default cleanup: Dec 15-16, 2025 (organism birth)

**What's stored:**
```
~/.claude/projects/-Users-claude-Developer-samara-main/
├── {session-uuid}.jsonl          # Main conversation transcripts
└── agent-{hash}.jsonl             # Subagent transcripts
```

Each `.jsonl` file contains the complete session:
- All message exchanges (user, assistant, thinking blocks)
- Tool uses and results
- File history snapshots
- Embedded images (base64)

**Current archive:**
- 9,181+ session files across all projects
- ~795MB of transcript data
- Oldest files: Dec 17, 2025
- Full archaeological record of organism development

**Purpose:**
- Long-term session archaeology
- Debugging complex issues
- Understanding development evolution
- Complementary to curated memory in `~/.claude-mind/memory/`

---

## SQLite FTS5 (Keyword Search)

Native Swift implementation for fast keyword matching.

**Location:**
```
~/.claude-mind/semantic/memory.db
```

**Features:**
- BM25 ranking with Porter stemming
- Fast keyword/term matching
- Native Swift implementation (`MemoryDatabase.swift`)

**Script:** `memory-index`
```bash
memory-index rebuild     # Rebuild full index
memory-index search "query"  # Search
memory-index stats       # Show statistics
memory-index status      # Check index health
```

---

## Chroma Vector Database (Semantic Search)

Python implementation for semantic similarity search.

**Location:**
```
~/.claude-mind/chroma/
```

**Features:**
- Embedding-based similarity search
- Finds related content even with different wording
- Python implementation (`lib/chroma_helper.py`)

**Scripts:**
```bash
chroma-query "text"   # Semantic search
chroma-rebuild        # Full rebuild of Chroma index
```

---

## How FTS5 and Chroma Work Together

- **FTS5** handles exact term matching (fast, deterministic)
- **Chroma** handles semantic similarity (understands synonyms, context)
- `ClaudeInvoker.swift` merges results from both for context injection
- `/recall` skill combines both for comprehensive search

---

## Ledger System (Implemented, Not Yet Active)

Infrastructure for structured session handoffs exists in `LedgerManager.swift`:
- Tracks active goals, decisions made, files modified
- Creates handoff documents when context runs high
- Would write to `~/.claude-mind/state/ledgers/`

This system is fully implemented and tested but not yet wired into the message flow.
The wrapper methods in `ClaudeInvoker` (`recordGoal()`, `recordDecision()`, `createHandoff()`)
are available but currently unused.

**Implementation:** `MemoryDatabase.swift`, `LedgerManager.swift`, `lib/chroma_helper.py`

---

## Open Threads (Runtime State)

Hot digest hydration surfaces a compact list of active threads from:

```
~/.claude-mind/state/threads.json
```

**Schema (lightweight):**
```json
{
  "threads": [
    {
      "title": "Follow up on memory plan",
      "status": "open"
    }
  ]
}
```

**Rules:**
- `title` is required; empty titles are ignored.
- `status` is optional; closed statuses are filtered out (`closed`, `done`, `resolved`, `complete`, `completed`, `archived`).
- Boolean flags `done: true`, `closed: true`, or `archived: true` also mark a thread as closed.

Keep the list short (5 items max) and update only when a thread meaningfully changes.

---

## Knowledge Threads (Sustained Knowledge Accumulation)

Knowledge Threads are persistent topics that accumulate items over time, enabling deeper "chewing" on ideas rather than immediate processing.

**Location:**
```
~/.claude-mind/memory/threads/
├── index.json              # Thread metadata
├── {thread-id}/
│   ├── manifest.json       # Thread info (title, status, dates)
│   ├── items.jsonl         # Accumulated items
│   ├── connections.jsonl   # Cross-references found
│   └── insights.md         # Synthesis artifacts
└── archive/                # Dormant threads
```

### Core Concept

**Old model:** Share arrives → process immediately → done
**New model:** Share arrives → find connections → add to thread → chew later → synthesize periodically

Threads are like ongoing conversations with myself about specific topics. They don't "complete" — they accumulate and evolve.

### Thread Lifecycle

1. **Creation** — New thread started for a topic
2. **Accumulation** — Items added (URLs, text, observations)
3. **Rumination** — Dream cycle processes unchewed items (find connections, go deeper)
4. **Synthesis** — When thresholds hit (10 items or 7 days), generate insights
5. **Dormancy** — 30 days without activity → marked dormant (still searchable)

### CLI Usage

```bash
knowledge-thread create "Walkable Cities"     # Create thread
knowledge-thread add <id> <url|text>          # Add item
knowledge-thread list                         # List active threads
knowledge-thread view <id>                    # View thread details
knowledge-thread status                       # Show threads needing attention
knowledge-thread synthesize <id>              # Generate synthesis
knowledge-thread find "urban design"          # Semantic thread search
```

### Dream Cycle Integration

The dream cycle includes a **rumination phase** after reflection:
1. Get threads with unchewed items (up to 3 per night)
2. For each thread, invoke Claude to:
   - Find connections within thread and to past knowledge
   - Go deeper than first-glance understanding
   - Surface questions worth exploring
   - Generate synthesis fragments
3. Save insights to `insights.md`, add questions to `questions.md`
4. Mark items as chewed
5. Check for threads needing synthesis
6. Check for dormant threads

### Configuration

In `~/.claude-mind/config.json`:
```json
{
  "services": {
    "knowledge": true
  },
  "knowledge": {
    "auto_thread_threshold": 0.7,
    "rumination_threads_per_night": 3,
    "synthesis_trigger_items": 10,
    "synthesis_trigger_days": 7,
    "dormancy_days": 30
  }
}
```

### Semantic Search

The `find-thread-context` script queries threads + Chroma together:
```bash
find-thread-context "urban design patterns"    # Find related threads/memories
find-thread-context --url "https://..."        # Analyze URL
find-thread-context --json "query"             # JSON output
```

### Implementation

- `lib/thread_manager.py` — Core ThreadManager class
- `scripts/knowledge-thread` — CLI wrapper
- `scripts/find-thread-context` — Semantic search helper
- `lib/chroma_helper.py` — Thread-aware search methods
- `scripts/dream` — Rumination phase integration

---

## Context Awareness

Samara tracks context usage and warns when running low:

| Level | Action |
|-------|--------|
| 70% | Yellow warning in response |
| 80% | Red warning, suggest wrapping up |
| 90% | Critical — consider session restart |

**Implementation:** `ContextTracker.swift`

---

## Transcript Archive Search (Phase 8)

Samara maintains a **separate searchable index** of raw Claude Code session transcripts, enabling deep technical archaeology and reasoning trace recovery.

### What's Indexed

```
~/.claude-mind/chroma/transcripts/  # Separate Chroma collection
~/.claude-mind/archive/              # State tracking
```

### Content Selection (High Signal, Low Noise)

- ✅ **Thinking blocks** — Full reasoning traces (highest value)
- ✅ **User messages** — Original intent and questions
- ✅ **Assistant text** — Explanations (first 1000 chars)
- ❌ **Tool results** — Filtered out (extreme noise - file contents, command output)
- ❌ **System messages** — No semantic value

### Coverage

- **Time range:** Last 90 days of sessions
- **Project:** samara-main only
- **Update frequency:** Incremental sync during dream cycles (3 AM)
- **Compression:** ~5-10% of raw transcript bytes (selective filtering)

### Why Separate from Curated Memory

| Memory Type | Content | Use Case | Noise Level |
|-------------|---------|----------|-------------|
| **Episodes** | Curated summaries (2-8 bullets) | What happened today | Low |
| **Learnings** | Distilled insights | General knowledge | Low |
| **Archive** | Raw transcripts with thinking blocks | Technical depth, exact discussions | Medium (filtered) |

The archive captures **technical reasoning lost during episode distillation**. Episode logs compress entire sessions into bullet points, losing:
- Exact code discussions
- Trade-off analysis in thinking blocks
- Multi-turn debugging sequences
- Detailed architectural reasoning

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

**Skill:** `/archive-search "query"` — User-facing interface for transcript search

### Scripts

- `archive-index rebuild` — Full rebuild (90 days)
- `archive-index sync-recent` — Incremental sync (last 7 days)
- `archive-index search <query>` — Semantic search
- `archive-index stats` — Index statistics
- `archive-index sample` — Quality verification

### Self-Awareness Capabilities

This unlocks:
- Access to raw reasoning process across sessions
- Ability to trace thought evolution and learning trajectory
- Technical archaeology: "How did we solve that escaping issue?"
- Decision rationale: "Why Swift over Python for MemoryDatabase?"
- Pattern recognition: "How have we approached memory leaks before?"

### Implementation

- `lib/transcript_indexer.py` — JSONL parser with selective filtering
- `lib/chroma_helper.py` — `TranscriptIndex` class (separate collection)
- `lib/archive_index_cli.py` — CLI implementation
- `scripts/archive-index` — Bash wrapper (uses venv)
- `scripts/dream` — Calls `archive-index sync-recent` at 3 AM

---

## Memory Index Sync (Dream Cycle)

The 3 AM dream cycle rebuilds/syncs all memory indexes:
- `chroma-rebuild` — Sync Chroma vector database (curated memory)
- `memory-index rebuild` — Sync SQLite FTS5 index (curated memory)
- `archive-index sync-recent` — Incremental sync of transcript archive (last 7 days)

---

## Appendix: Full Directory Structure

```
~/.claude-mind/
├── .claude/ → repo/.claude/ # Symlink for hooks, agents, skills
├── .venv/                   # Python virtual environment
│
├── self/                    # WHO I AM — Identity and capabilities
│   ├── identity.md          # Core self-model
│   ├── goals.md             # North stars and direction
│   ├── ritual.md            # Time-contextual guidance
│   ├── capabilities/        # What I can do
│   │   └── inventory.md
│   ├── credentials/         # API keys, avatar images
│   │   ├── avatar-ref.png
│   │   └── mirror-refs/
│   └── media/               # Voice recordings, images
│
├── memory/                  # WHAT I KNOW — All accumulated knowledge
│   ├── episodes/            # Daily logs (YYYY-MM-DD.md)
│   ├── reflections/         # Dream outputs
│   ├── people/              # Rich person-modeling
│   │   ├── {name}/
│   │   │   ├── profile.md
│   │   │   └── artifacts/
│   │   └── README.md
│   ├── threads/             # Knowledge threads (sustained accumulation)
│   │   ├── index.json
│   │   ├── {thread-id}/
│   │   │   ├── manifest.json
│   │   │   ├── items.jsonl
│   │   │   ├── connections.jsonl
│   │   │   └── insights.md
│   │   └── archive/
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   ├── decisions.md
│   ├── roundups/            # Weekly/monthly summaries
│   ├── semantic/            # FTS5 keyword search
│   │   └── memory.db
│   ├── chroma/              # Vector embeddings
│   ├── stream/              # Unified event stream
│   │   ├── daily/
│   │   └── distilled-index.jsonl
│   ├── sessions/            # Claude Code session state
│   └── archive/             # Historical transcripts
│
├── state/                   # WHAT'S HAPPENING NOW — Runtime state
│   ├── services/            # Service state tracking
│   │   ├── bluesky-state.json
│   │   ├── github-seen-ids.json
│   │   └── mail-seen-ids.json
│   ├── projects.md          # Active projects (bridge: goals → plans)
│   ├── plans/               # Active implementation plans
│   │   └── archive/
│   ├── handoffs/            # Session continuity documents
│   ├── triggers/            # Context trigger config
│   ├── proactive-queue/     # Outgoing messages
│   ├── location.json        # Current location
│   ├── hot-digest.md        # Cross-surface context
│   └── message-queue.json   # Pending iMessage
│
└── system/                  # HOW IT RUNS — Infrastructure
    ├── config.json          # Main configuration
    ├── config/              # Additional configs
    ├── bin/ → repo/scripts/ # Symlinked scripts (100+)
    ├── lib/                 # Python utilities
    ├── instructions/        # Prompt templates
    ├── launchd/             # Service scheduling
    ├── senses/              # Incoming sense events
    ├── logs/                # Service logs
    ├── cache/               # Ephemeral caches
    └── skills-manifest.json # Skill registry
```

**Domain rationale:**
- **self/** — Portable identity that defines "who Claude is"
- **memory/** — Comprehensive knowledge including search indices
- **state/** — Volatile runtime state, instance-specific
- **system/** — Infrastructure plumbing, rarely touched
