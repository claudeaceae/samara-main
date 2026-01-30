# Skills Reference

Complete catalog of interactive skills available via Claude Code. Invoke with `/skillname` or trigger naturally.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Core System

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/status` | System health check (Samara, wake cycles, FDA) | status, health, running, broken, check |
| `/sync` | Check for drift between repo and runtime | sync, drift, "out of sync", system drift |
| `/maintenance` | Organism maintenance (drift, symlinks, services) | maintenance, health check, drift |
| `/samara` | Debug/restart Samara, view logs | samara, messages, "not working", restart, logs |
| `/services` | Toggle services on/off (X, Bluesky, GitHub, wallet, etc.) | services, enable, disable, toggle |

---

## Memory & Recall

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/memory` | Search learnings, decisions, observations | memory, remember, recall, search, find, "what did I learn", past |
| `/recall` | Semantic memory search (FTS5 + Chroma) for associative recall | "when did we", "last time", history, previous, before, "that conversation" |
| `/stream` | Query unified event stream by surface (cli, imessage, wake, etc.) | stream, recent activity, "what happened", today |
| `/archive-search` | Search raw session transcripts for technical details and reasoning traces | archive, transcript, session, raw log |
| `/episode` | View/append today's episode log | episode, today, log, "what happened", record |
| `/learning` | Access accumulated learnings and technical discoveries | learning, learned, insights |
| `/observation` | Access observations about patterns, behaviors, and the world | observation, observed, patterns |

---

## Reflection & Learning

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/reflect` | Quick capture learning/observation/insight | reflect, noticed, realized, insight, learned |
| `/decide` | Document decision with rationale | decide, decision, chose, choice, "why did we", trade-off |
| `/decision` | Access past decisions with their rationale (read-only) | decision, "why did we decide", rationale |
| `/iterate` | Autonomous iteration until success criteria met | iterate, "keep trying", autonomous, persist |

---

## Context & Awareness

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/morning` | Morning briefing (calendar, location, context) | morning, briefing, "what's up", overview, today, schedule |
| `/location` | Current location with patterns | location, "where am I", nearby, here |
| `/capability` | Check if action is possible | "can I", capability, "able to", permission, possible |
| `/senses` | Monitor and test sense event system | senses, sense events, diagnose |

---

## People

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/person` | View or create person profile | person, "who is", profile, about (followed by name) |
| `/note` | Quick observation about a person | note, "about [name]", noticed, jot down |
| `/artifact` | Add file to person's artifacts | artifact, save, "add photo", attach, store |

---

## Communication

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/email` | Check and respond to email | email, inbox, mail, unread, messages |
| `/invites` | View and manage calendar invitations (CalDAV), accept/decline, create events | invites, calendar, meeting, accept, decline |
| `/webhook` | Manage webhook sources - add, test, view events | webhook, "add webhook", "incoming webhooks" |

---

## Visual Expression

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/generate-image` | Generate images; **primary tool for visual self-expression** | generate, "create image", draw, selfie, express, react, feel, emotion |
| `/look` | Capture photo from webcam | look, see, webcam, camera, photo, "what's around" |

---

## Finance

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/wallet` | Check crypto wallet balances, addresses, and history | wallet, balance, SOL, ETH, BTC, address, crypto |

---

## Debugging

| Skill | Purpose | Triggers |
|-------|---------|----------|
| `/debug-session` | Debug Claude Code session issues | session, batch, "group chat", scrambled, routing |
| `/diagnose-leaks` | Diagnose thinking/session ID leaks | leak, "thinking trace", "session id", sanitization |

---

## Skill Definitions

Skills are defined in `.claude/skills/` and symlinked to `~/.claude/skills/`.

Each skill has a `SKILL.md` file that defines:
- Trigger conditions (when to invoke)
- Execution steps
- Required scripts and dependencies
