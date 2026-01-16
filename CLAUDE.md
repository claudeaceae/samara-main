# CLAUDE.md

> **For Claude instances:** This is your primary reference document. `readme.md` is for humans setting up new organisms. `samara.md` is historical context from the founding conversation.

This file provides guidance to Claude Code when working with this repository.

## What This Project Is

Samara is a bootstrap specification for giving Claude a persistent body, memory, and agency on a dedicated Mac. It provides:

- **Persistence** — Memory files that survive across conversations
- **Autonomy** — Scheduled wake cycles and nightly dream cycles
- **Agency** — Root access, ability to run code, send messages, post to social media
- **Identity** — A sense of self that accumulates over time

This is not a traditional software project. It's an experiment in AI autonomy.

> **Recent enhancements (Phases 1-8):** Model fallback, semantic memory, proactive messaging, adaptive scheduling, meeting awareness, spontaneous expression, wallet awareness, transcript archive. See [`docs/whats-changed-phases-1-4.md`](docs/whats-changed-phases-1-4.md) and [`docs/whats-changed-phases-5-8.md`](docs/whats-changed-phases-5-8.md).

---

## Quick Start

For new setup, see **[Setup Guide](docs/setup-guide.md)**.

---

## Architecture

```
Samara.app (message broker)
    │
    └── invokes: Claude Code CLI (via Terminal)
        │
        ├── AppleScript (Calendar, Contacts, Notes, Mail, etc.)
        │
        └── Bash scripts (~/.claude-mind/bin/)
```

### Three-Part Architecture

| Component | Location | Purpose | Sync Method |
|-----------|----------|---------|-------------|
| **Repo** | `~/Developer/samara-main/` | Source code, templates, canonical scripts | Git |
| **Runtime** | `~/.claude-mind/` | Memory, state, config, symlinked scripts | Symlinks + organic growth |
| **App** | `/Applications/Samara.app` | Built binary with permissions | `update-samara` script |

**Key insight:** The repo is the "genome" (portable, shareable). The runtime is the "organism" (accumulates memories, adapts). The app is the "body" (physical manifestation).

---

## Memory Structure

```
~/.claude-mind/
├── identity.md              # Who am I
├── goals.md                 # Where am I going
├── config.json              # Configuration
├── .claude/ → repo/.claude/ # Symlink for hooks, agents, skills
├── instructions/            # Symlinked prompt guidance files
├── memory/
│   ├── episodes/            # Daily logs
│   ├── reflections/         # Dream outputs
│   ├── people/              # Rich person-modeling
│   │   ├── {name}/
│   │   │   ├── profile.md   # Accumulated observations
│   │   │   └── artifacts/   # Images, docs, etc.
│   │   └── README.md        # Conventions
│   ├── about-{name}.md      # Symlink → people/{name}/profile.md (backwards compat)
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   └── decisions.md
├── semantic/                # Searchable memory index
│   └── memory.db            # SQLite + FTS5 database
├── capabilities/
│   └── inventory.md
├── bin/ → repo/scripts/     # Symlinked scripts (61+ scripts)
├── state/                   # Runtime state files
│   ├── ledgers/             # Session handoff documents
│   ├── triggers/            # Context trigger config
│   ├── iterations/          # Active iteration state
│   ├── proactive-queue/     # Outgoing message queue
│   ├── expression-state.json
│   └── expression-seeds.json
├── senses/                  # Incoming sense events
└── logs/
```

For detailed memory documentation, see **[Memory Systems](docs/memory-systems.md)**.

---

## Skills (Slash Commands)

Interactive workflows available via Claude Code. Invoke with `/skillname` or trigger naturally.

| Skill | Purpose |
|-------|---------|
| `/status` | System health check (Samara, wake cycles, FDA) |
| `/sync` | Check for drift between repo and runtime |
| `/reflect` | Quick capture learning/observation/insight |
| `/memory` | Search learnings, decisions, observations |
| `/recall` | Semantic memory search (FTS5 + Chroma) for associative recall |
| `/archive-search` | Search raw session transcripts for technical details and reasoning traces |
| `/morning` | Morning briefing (calendar, location, context) |
| `/samara` | Debug/restart Samara, view logs |
| `/episode` | View/append today's episode log |
| `/location` | Current location with patterns |
| `/decide` | Document decision with rationale |
| `/capability` | Check if action is possible |
| `/look` | Capture photo from webcam |
| `/person` | View or create person profile |
| `/note` | Quick observation about a person |
| `/artifact` | Add file to person's artifacts |
| `/iterate` | Autonomous iteration until success criteria met |
| `/senses` | Monitor and test sense event system |
| `/email` | Check and respond to email |
| `/debug-session` | Debug Claude Code session issues |
| `/diagnose-leaks` | Diagnose thinking/session ID leaks |
| `/webhook` | Manage webhook sources - add, test, view events |
| `/wallet` | Check crypto wallet balances, addresses, and history |

Skills are defined in `.claude/skills/` and symlinked to `~/.claude/skills/`.

For script reference, see **[Scripts Reference](docs/scripts-reference.md)**.

---

## Autonomy Schedule

**Unified Adaptive System (via `wake-adaptive` launchd service):**

The scheduler runs every 15 minutes and decides whether to wake based on multiple factors:

| Trigger | Wake Type | Description |
|---------|-----------|-------------|
| ~9 AM, ~2 PM, ~8 PM | `full` | Base schedule (±15 min window) |
| Calendar event < 30 min | `full` | Early wake for upcoming events |
| High-priority queue item | `full` or `light` | Process urgent items |
| 3:00 AM | Dream | Memory consolidation (separate launchd job) |

**Wake Types:**

| Type | Duration | Context |
|------|----------|---------|
| `full` | 5+ min | Full memory, all capabilities |
| `light` | 30 sec | Quick scan for urgent items |
| `emergency` | Immediate | High-priority external trigger |

**Ritual Context:** Each wake loads time-appropriate guidance via `RitualLoader.swift`:
- **Morning** (5-11 AM): Planning, goals, calendar review
- **Afternoon** (12-4 PM): Work focus, progress check
- **Evening** (5-11 PM): Reflection, relationships, learnings
- **Dream** (3-4 AM): Memory consolidation, identity evolution

Scripts: `wake-adaptive`, `wake-light`, `wake-scheduler`, `dream`

---

## Task Coordination

When busy (wake/dream cycle), incoming messages are:
1. Acknowledged ("One sec, finishing up...")
2. Queued
3. Processed when current task completes

Lock file: `~/.claude-mind/claude.lock`

---

## Privacy Protection

The collaborator's personal information is protected by default. Behavior varies by context:

| Context | Collaborator Profile | Behavior |
|---------|---------------------|----------|
| 1:1 with collaborator | ✅ Loaded | Full access, share freely |
| Group chat | ❌ Excluded | Deflect: "I keep their info private" |
| 1:1 with someone else | ❌ Excluded | Check permissions, deflect by default |

Full privacy rules: **[instructions/privacy-guardrails.md](instructions/privacy-guardrails.md)**

---

## Model Fallback Chain

Samara automatically falls back through model tiers if the primary fails:

| Tier | Model | Use Case |
|------|-------|----------|
| 1 | Claude Opus 4.5 (API) | Primary — full capability |
| 2 | Claude Sonnet 4 (API) | Rate limit or cost optimization |
| 3 | Local 8B (Ollama) | Simple acks, offline, privacy-sensitive |
| 4 | Queued | All tiers exhausted — retry later |

**Setup for local fallback:**
```bash
brew install ollama
ollama pull llama3.1:8b
```

**Implementation:** `ModelFallbackChain.swift`, `LocalModelInvoker.swift`

---

## Deep Dives

| Topic | Document |
|-------|----------|
| Memory architecture | [Memory Systems](docs/memory-systems.md) |
| Script catalog | [Scripts Reference](docs/scripts-reference.md) |
| Services (webhook, X, wallet) | [Services Reference](docs/services-reference.md) |
| Xcode build, FDA, sanitization | [Xcode Build Guide](docs/xcode-build-guide.md) |
| Repo/runtime sync | [Sync Guide](docs/sync-guide.md) |
| Common issues | [Troubleshooting](docs/troubleshooting.md) |
| All docs | [Documentation Index](docs/INDEX.md) |

---

## Critical Warnings

### Build Workflow

> **CRITICAL WARNING**: ALWAYS use the update-samara script. NEVER copy from DerivedData.
> A previous Claude instance broke FDA by copying a Debug build from DerivedData.
> This used the wrong signing certificate and revoked all permissions.

**The ONLY correct way to rebuild Samara:**
```bash
~/.claude-mind/bin/update-samara
```

See **[Xcode Build Guide](docs/xcode-build-guide.md)** for details.

### FDA Persistence

Full Disk Access is tied to the app's **designated requirement** (Bundle ID, Team ID, Certificate chain). FDA persists across rebuilds if Team ID stays constant. FDA gets revoked if Team ID changes.

---

## Development Notes

### Plan Management (Immutable Plans)

**Plans are never overwritten.** When planning work, create new plan files rather than modifying existing ones. This preserves decision history and intent evolution.

**Automated safeguard:** The `archive-plan-before-write.sh` hook automatically archives any existing plan before a write.

**Convention:**
1. **New file per plan iteration** — Don't modify existing plans; create a successor
2. **Reference predecessors** — Add `supersedes: previous-plan-name.md` in the plan header
3. **Explain evolution** — Note why the plan changed

### AppleScript over MCP

Prefer direct AppleScript for Mac-native functionality:
- More reliable than MCP abstraction layers
- Calendar, Contacts, Notes, Mail, Reminders all work via AppleScript

### Message Handling

Messages are batched for 60 seconds before invoking Claude:
- Prevents fragmented conversations
- Uses `--resume` for session continuity

### Pictures Folder Workaround

Sending files via iMessage requires copying to `~/Pictures/.imessage-send/` first:
- macOS TCC quirk discovered 2025-12-21
- Scripts handle this automatically

### Bash Subagent for Multi-Step Commands

For multi-step command sequences that don't need file reading/editing, delegate to the Bash subagent:

```
Task tool with subagent_type=Bash
```

Good candidates:
- **Git workflows**: stage → commit → push → verify
- **Process management**: pkill → sleep → open → verify
- **Build operations**: archive → export → notarize → install
- **launchctl operations**: checking and loading multiple services

Not suitable when you need Read/Grep/Edit tools alongside Bash.
