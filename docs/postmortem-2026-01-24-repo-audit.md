# Repo Audit Postmortem — January 24, 2026

Comprehensive audit of the samara-main repository to identify and fix inconsistencies, stale content, and documentation gaps.

---

## Executive Summary

This audit walked through every directory and root file in the repository, identifying path inconsistencies (particularly around the 4-domain architecture), missing documentation, stale references, and structural issues. The primary finding was that the codebase had drifted from a flat structure to a 4-domain architecture (`self/`, `memory/`, `state/`, `system/`) but this migration was incomplete — some services, tests, templates, and documentation still referenced old paths.

**Key metrics:**
- Directories audited: 7 (`docs/`, `lib/`, `scripts/`, `services/`, `templates/`, `tests/`, `create-samara/`)
- Root files audited: 10
- Files created: 8 READMEs
- Files modified: 30+
- Services fixed: 3 (path corrections)
- Tests fixed: 5 (path corrections)
- Templates fixed: 2 (content updates)

---

## Directory-by-Directory Findings

### 1. docs/

**Issues found:**
- `memory-systems.md`: Referenced non-existent `docs/contiguous-memory-system.md`
- `xcode-build-guide.md`: Wrong path `~/.claude-mind/bin/` → should be `system/bin/`
- `scripts-reference.md`: Wrong credentials and bin paths
- `services-reference.md`: Wrong credentials paths, missing services
- `skills-reference.md`: Missing 3 skills (`/learning`, `/observation`, `/decision`)
- `sync-guide.md`: Wrong bin paths

**Changes made:**
- Fixed all path references to use 4-domain architecture
- Converted `scripts-reference.md` and `services-reference.md` to redirects (primary docs now live alongside code)
- Added missing skills to skills-reference.md
- Added Testing section to INDEX.md

---

### 2. lib/

**Issues found:**
- No README.md documenting the 21 Python utilities

**Changes made:**
- Created comprehensive `lib/README.md` documenting all utilities by category:
  - Core (mind_paths, config_loader, logging_config)
  - Memory Search (chroma_helper, memory_search)
  - Event Stream (stream_writer, stream_distill, hot_digest_builder, etc.)
  - Context (calendar_analyzer, weather_helper, location_analyzer, pattern_analyzer)
  - Questions (question_synthesizer, trigger_evaluator)
  - Analytics (roundup_aggregator, privacy_filter, session_summarizer)
- Added to docs/INDEX.md

---

### 3. scripts/

**Issues found:**
- ~90 scripts with no comprehensive documentation
- `docs/scripts-reference.md` was outdated and incomplete
- Path inconsistencies between `~/.claude-mind/bin/` and `~/.claude-mind/system/bin/`

**Changes made:**
- Created comprehensive `scripts/README.md` documenting all scripts across 18 categories
- Converted `docs/scripts-reference.md` to a redirect
- Fixed path references in sync-guide.md
- Updated CLAUDE.md and docs/INDEX.md references

---

### 4. services/

**Issues found:**
- 4 services missing READMEs (bluesky-watcher, github-watcher, wallet-watcher, x-watcher)
- Path inconsistencies in existing READMEs
- **Critical:** 3 services using wrong paths in actual code:
  - `location-receiver/server.py`: `senses/` instead of `system/senses/`
  - `webhook-receiver/server.py`: `senses/` and `credentials/` instead of `system/senses/` and `self/credentials/`
  - `mcp-memory-bridge/server.py`: `identity.md` and `goals.md` at root instead of `self/`

**Changes made:**
- Created 4 missing READMEs
- Fixed path inconsistencies in existing READMEs
- **Fixed service code** to use correct 4-domain paths
- Created `services/README.md` as central index
- Converted `docs/services-reference.md` to a redirect

---

### 5. templates/

**Issues found:**
- `ritual.template.md`: Had "Exploration" wake type that was never implemented in RitualLoader.swift
- `inventory.template.md`:
  - Wrong paths (`~/.claude-mind/bin/` instead of `system/bin/`)
  - Missing services (X/Twitter, wallet, location, webhook, MCP bridge, meeting check)
  - Missing capabilities (image generation, semantic search)
- `birth.sh`:
  - Not installing `ritual.template.md`
  - Using old flat directory structure
  - Instructions were copies, not symlinks
- No README.md documenting template system

**Changes made:**
- Removed "Exploration" wake type from ritual.template.md (not implemented)
- Rewrote inventory.template.md with correct paths and complete service/capability list
- Updated birth.sh:
  - Added ritual.template.md installation
  - Changed to 4-domain directory structure
  - Changed instructions to symlinks for auto-updates
- Created `templates/README.md` with complete placeholder documentation
- Converted runtime instructions to symlinks

---

### 6. tests/

**Issues found:**
- Test fixtures used old flat structure instead of 4-domain
- `config.json` in fixtures missing fields (entity.x, collaborator.x, services)
- 5 test files hardcoding old paths:
  - `test_location_receiver.py`
  - `test_bluesky_watcher.py`
  - `test_github_watcher.py`
  - `test_webhook_receiver.py`
  - `test_webhook_receiver_http.py`
- README.md was minimal

**Changes made:**
- Restructured `fixtures/claude-mind/` to 4-domain architecture
- Updated `fixtures/claude-mind/config.json` with complete fields
- Fixed all 5 test files to use correct paths
- Rewrote `tests/README.md` with comprehensive documentation

---

### 7. create-samara/ (formerly cli/)

**Issues found:**
- Directory named `cli/` but contained single-purpose `create-samara` npm package
- Package not published to npm, so `npx create-samara` references in docs didn't work
- No README.md

**Changes made:**
- Renamed `cli/` → `create-samara/` to match package name
- Created `create-samara/README.md`
- Updated all references in bootstrap.sh, readme.md, docs/INDEX.md
- Updated package.json repository.directory

---

## Root Files Audit

| File | Status | Changes |
|------|--------|---------|
| `.gitignore` | Updated | Added `.mcp.json` to ignore |
| `.mcp.json` | Fixed | Renamed to `.mcp.example.json`, replaced hardcoded paths |
| `AGENTS.md` | Good | Symlink to CLAUDE.md (unchanged) |
| `birth.sh` | Fixed | 4-domain structure, ritual template, symlinks |
| `bootstrap.sh` | Fixed | Removed non-existent npx command, fixed clone path, added manual steps |
| `CLAUDE.md` | Good | Already accurate (unchanged) |
| `config.example.json` | Good | Already accurate (unchanged) |
| `package.json` | Good | Minimal dependencies (unchanged) |
| `readme.md` | Fixed | Multiple path fixes, removed non-existent doc references, updated setup instructions |
| `samara.md` | Historical | Preserved as-is (unchanged) |

---

## Key Patterns Established

### 4-Domain Architecture

The runtime (`~/.claude-mind/`) uses this structure:

```
~/.claude-mind/
├── self/           # WHO I AM (identity, goals, credentials)
├── memory/         # WHAT I KNOW (episodes, people, learnings)
├── state/          # WHAT'S HAPPENING (services, plans, location)
└── system/         # HOW IT RUNS (bin, lib, logs, senses, instructions)
```

All code, tests, templates, and documentation should reference these paths:
- ✅ `~/.claude-mind/system/bin/`
- ✅ `~/.claude-mind/system/senses/`
- ✅ `~/.claude-mind/system/logs/`
- ✅ `~/.claude-mind/self/credentials/`
- ✅ `~/.claude-mind/self/identity.md`
- ❌ `~/.claude-mind/bin/` (old)
- ❌ `~/.claude-mind/senses/` (old)
- ❌ `~/.claude-mind/credentials/` (old)

### Documentation Lives With Code

Primary documentation should live alongside the code it documents:
- `scripts/README.md` (not `docs/scripts-reference.md`)
- `services/README.md` (not `docs/services-reference.md`)
- `lib/README.md`
- `templates/README.md`
- `tests/README.md`
- `create-samara/README.md`

The `docs/` directory contains:
- Setup guides
- Architecture documentation
- Cross-cutting concerns (memory systems, troubleshooting)
- INDEX.md as navigation hub

### Template vs Runtime

- Templates in repo use `{{placeholders}}` and represent "base state"
- Runtime files evolve independently after birth
- Instructions should be symlinked (auto-update) not copied

---

## Files Created

1. `lib/README.md`
2. `scripts/README.md` (major rewrite)
3. `services/README.md`
4. `services/bluesky-watcher/README.md`
5. `services/github-watcher/README.md`
6. `services/wallet-watcher/README.md`
7. `services/x-watcher/README.md`
8. `templates/README.md`
9. `tests/README.md` (major rewrite)
10. `create-samara/README.md`
11. `.mcp.example.json`

---

## Files Significantly Modified

### Service Code (Bug Fixes)
- `services/location-receiver/server.py` — SENSES_DIR path
- `services/webhook-receiver/server.py` — SENSES_DIR and CREDENTIALS_DIR paths
- `services/mcp-memory-bridge/server.py` — identity.md and goals.md paths

### Templates
- `templates/ritual.template.md` — Removed unimplemented Exploration section
- `templates/inventory.template.md` — Complete rewrite with correct paths and services
- `birth.sh` — 4-domain structure, ritual template, symlinks

### Tests
- `tests/python/test_location_receiver.py`
- `tests/python/test_bluesky_watcher.py`
- `tests/python/test_github_watcher.py`
- `tests/python/test_webhook_receiver.py`
- `tests/python/test_webhook_receiver_http.py`
- `tests/fixtures/claude-mind/` — Restructured to 4-domain
- `tests/fixtures/claude-mind/config.json` — Added missing fields

### Documentation
- `docs/INDEX.md`
- `docs/memory-systems.md`
- `docs/xcode-build-guide.md`
- `docs/sync-guide.md`
- `docs/skills-reference.md`
- `docs/scripts-reference.md` (converted to redirect)
- `docs/services-reference.md` (converted to redirect)
- `readme.md`
- `bootstrap.sh`
- `CLAUDE.md` (minor reference updates)

### Renamed
- `cli/` → `create-samara/`
- `.mcp.json` → `.mcp.example.json`

---

## Recommendations for Future

1. **Automated path checking**: Consider a CI check that greps for old-style paths (`~/.claude-mind/bin/`, `~/.claude-mind/senses/`, etc.)

2. **Publish create-samara**: The CLI wizard is complete and functional. Publishing to npm would enable `npx create-samara` as documented.

3. **Template drift detection**: The templates should periodically be compared against runtime to ensure they still represent accurate "base state"

4. **Service toggleability**: All new services should follow the toggleability pattern documented in CLAUDE.md

5. **Documentation reviews**: When adding features, update both the inline README and docs/ as appropriate

---

## Session Statistics

- Duration: ~3 hours
- Directories audited: 7
- Root files audited: 10
- Files created: 11
- Files modified: 30+
- Services with code fixes: 3
- Tests with path fixes: 5
- Git operations: 1 rename (cli → create-samara)
