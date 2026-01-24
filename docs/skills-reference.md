# Skills Reference

Complete catalog of interactive skills available via Claude Code. Invoke with `/skillname` or trigger naturally.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Core System

| Skill | Purpose |
|-------|---------|
| `/status` | System health check (Samara, wake cycles, FDA) |
| `/sync` | Check for drift between repo and runtime |
| `/maintenance` | Organism maintenance (drift, symlinks, services) |
| `/samara` | Debug/restart Samara, view logs |
| `/services` | Toggle services on/off (X, Bluesky, GitHub, wallet, etc.) |

---

## Memory & Recall

| Skill | Purpose |
|-------|---------|
| `/memory` | Search learnings, decisions, observations |
| `/recall` | Semantic memory search (FTS5 + Chroma) for associative recall |
| `/stream` | Query unified event stream by surface (cli, imessage, wake, etc.) |
| `/archive-search` | Search raw session transcripts for technical details and reasoning traces |
| `/episode` | View/append today's episode log |

---

## Reflection & Learning

| Skill | Purpose |
|-------|---------|
| `/reflect` | Quick capture learning/observation/insight |
| `/decide` | Document decision with rationale |
| `/iterate` | Autonomous iteration until success criteria met |

---

## Context & Awareness

| Skill | Purpose |
|-------|---------|
| `/morning` | Morning briefing (calendar, location, context) |
| `/location` | Current location with patterns |
| `/capability` | Check if action is possible |
| `/senses` | Monitor and test sense event system |

---

## People

| Skill | Purpose |
|-------|---------|
| `/person` | View or create person profile |
| `/note` | Quick observation about a person |
| `/artifact` | Add file to person's artifacts |

---

## Communication

| Skill | Purpose |
|-------|---------|
| `/email` | Check and respond to email |
| `/invites` | View and manage calendar invitations (CalDAV), accept/decline, create events |
| `/webhook` | Manage webhook sources - add, test, view events |

---

## Visual Expression

| Skill | Purpose |
|-------|---------|
| `/generate-image` | Generate images; **primary tool for visual self-expression** |
| `/look` | Capture photo from webcam |

---

## Finance

| Skill | Purpose |
|-------|---------|
| `/wallet` | Check crypto wallet balances, addresses, and history |

---

## Debugging

| Skill | Purpose |
|-------|---------|
| `/debug-session` | Debug Claude Code session issues |
| `/diagnose-leaks` | Diagnose thinking/session ID leaks |

---

## Skill Definitions

Skills are defined in `.claude/skills/` and symlinked to `~/.claude/skills/`.

Each skill has a `SKILL.md` file that defines:
- Trigger conditions (when to invoke)
- Execution steps
- Required scripts and dependencies
