# CLAUDE.md

> **For Claude instances:** This is your primary reference document. `readme.md` is for humans setting up new organisms. `samara.md` is historical context from the founding conversation.

This file provides guidance to Claude Code when working with this repository.

## What This Project Is

Samara is a bootstrap specification for giving Claude a persistent body, memory, and agency on a dedicated Mac. It provides persistence (memory files), autonomy (scheduled wake cycles), agency (root access, messaging, posting), and identity (accumulating sense of self).

This is not a traditional software project. It's an experiment in AI autonomy.

> **Key capabilities:** Model fallback chain, semantic memory search, proactive messaging, adaptive wake scheduling, meeting awareness, wallet awareness. See [Memory Systems](docs/memory-systems.md) and [Services Reference](services/README.md).

---

## Critical Warnings

### Build Workflow

> **CRITICAL WARNING**: ALWAYS use the update-samara script. NEVER copy from DerivedData.
> A previous Claude instance broke FDA by copying a Debug build from DerivedData.
> This used the wrong signing certificate and revoked all permissions.

**The ONLY correct way to rebuild Samara:**
```bash
~/.claude-mind/system/bin/update-samara
```

See **[Xcode Build Guide](docs/xcode-build-guide.md)** for details.

### FDA Persistence

Full Disk Access is tied to the app's **designated requirement** (Bundle ID, Team ID, Certificate chain). FDA persists across rebuilds if Team ID stays constant. FDA gets revoked if Team ID changes.

---

## Architecture

```
Samara.app (message broker)
    └── invokes: Claude Code CLI (via Terminal)
        ├── AppleScript (Calendar, Contacts, Notes, Mail, etc.)
        └── Bash scripts (~/.claude-mind/system/bin/)
```

| Component | Location | Purpose | Sync Method |
|-----------|----------|---------|-------------|
| **Repo** | `~/Developer/samara-main/` | Source code, templates, canonical scripts | Git |
| **Runtime** | `~/.claude-mind/` | Memory, state, config, symlinked scripts | Symlinks + organic growth |
| **App** | `/Applications/Samara.app` | Built binary with permissions | `update-samara` script |

The repo is the "genome" (portable, shareable). The runtime is the "organism" (accumulates memories, adapts). The app is the "body" (physical manifestation).

---

## Memory Structure (4-Domain Architecture)

| Domain | Purpose | Key Contents |
|--------|---------|--------------|
| **self/** | WHO I AM | identity.md, goals.md, credentials/ |
| **memory/** | WHAT I KNOW | episodes/, people/, learnings.md, chroma/ |
| **state/** | WHAT'S HAPPENING | services/, plans/, projects.md, location.json |
| **system/** | HOW IT RUNS | config.json, bin/, lib/, logs/, instructions/ |

**Strictly enforced:** Nothing else belongs at runtime root. See [Memory Systems](docs/memory-systems.md) for detailed layout.

**Project tracking:** `goals.md` (direction) → `state/projects.md` (tracking) → `state/plans/` (details). Completed plans move to `archive/`.

---

## Skills

Invoke with `/skillname`. Full catalog: **[Skills Reference](docs/skills-reference.md)**

---

## Deep Dives

| Topic | Document |
|-------|----------|
| Memory architecture | [Memory Systems](docs/memory-systems.md) |
| Script catalog | [Scripts Reference](scripts/README.md) |
| Services (webhook, X, wallet) | [Services Reference](services/README.md) |
| Xcode build, FDA, sanitization | [Xcode Build Guide](docs/xcode-build-guide.md) |
| Repo/runtime sync | [Sync Guide](docs/sync-guide.md) |
| Common issues | [Troubleshooting](docs/troubleshooting.md) |
| Development patterns | [Development Patterns](docs/development-patterns.md) |
| All docs | [Documentation Index](docs/INDEX.md) |

---

## Development Notes

### Path Safety

**ALWAYS use absolute paths** when writing to runtime directories:
- `~/.claude-mind/state/...` or `/Users/claude/.claude-mind/...`
- NEVER `.claude-mind/state/...` (creates directory in current working directory)

Automated safeguard: `block-wrong-path-writes` in the pre-tool dispatcher.

### Plan Management (Immutable Plans)

**Plans are never overwritten.** Create new plan files rather than modifying existing ones. The `archive-plan-before-write` hook auto-archives existing plans.

Convention: New file per iteration, reference predecessors with `supersedes:` header, explain evolution.

### Implementing New Senses/Services

**All new senses and services MUST be toggleable.** You must:

1. Add to `ServicesConfig` (`Configuration.swift`) with `isEnabled()` case
2. Guard the handler in `SenseRouter.swift`
3. Update `service-toggle` script
4. Update `config.json` (default: `true`)
5. Document in `/services` skill

See existing implementations (x, bluesky, wallet) for patterns. Additional patterns: **[Development Patterns](docs/development-patterns.md)**.
