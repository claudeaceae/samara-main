# Plan: Local Qwen3 Integration for Safe Background Tasks

## Summary

Leverage Ollama 0.14.0+'s Anthropic API compatibility to run full Claude Code agentic loops with local Qwen3 for maintenance tasks. The local model gets the full toolset (Read, Grep, Glob, Bash) but with explicit guardrails preventing any voice/memory/relationship operations.

## Core Principle

**Local model can DETECT and CLASSIFY, but not GENERATE content that becomes part of identity/voice/relationship.**

## Safe Boundaries

### Local Model CAN Do:
- Health monitoring (check services, logs, disk space, FDA status)
- Drift detection (compare repo vs runtime, symlink integrity)
- Log analysis (parse errors, find patterns)
- Stale file identification (find unused/outdated entries)
- Triage classification (urgent vs normal vs background)

### Local Model CANNOT Do:
- Write to identity.md, goals.md, decisions.md
- Write episode entries or reflections
- Update person profiles
- Send any messages (iMessage, email, Bluesky)
- Make git commits
- Call external APIs

## Implementation

### 1. Local Maintenance Wrapper Script

**New file: `scripts/local-maintenance`**

Invokes Claude Code with local Qwen3:
```bash
ANTHROPIC_AUTH_TOKEN=ollama \
ANTHROPIC_BASE_URL=http://localhost:11434 \
claude --model ollama:qwen3 \
  --agent ~/.claude/agents/local-$TASK.md \
  --max-turns 10 \
  --dangerously-skip-permissions \
  --output-format json
```

Supports tasks: `drift-check`, `health-check`, `log-triage`

### 2. Guardrail Configuration

**New file: `~/.claude-mind/config/local-model-boundaries.json`**

Explicit denylist for file writes and bash commands:
- Files: identity.md, goals.md, episodes/*, reflections/*, people/**, learnings.md, etc.
- Commands: osascript, message, bluesky-post, git push, curl POST

### 3. PreToolUse Hook for Enforcement

**New file: `.claude/hooks/local-model-guardrail.sh`**

Blocks prohibited operations for `ollama:*` model sessions:
- Validates Write/Edit targets against allowlist
- Blocks dangerous bash commands
- Logs all blocks to audit trail

### 4. Local Agents (Read-Only)

**New agents in `.claude/agents/`:**

| Agent | Purpose | Output |
|-------|---------|--------|
| `local-drift-check.md` | Compare repo vs runtime | JSON with findings |
| `local-health-check.md` | Service/FDA/disk checks | JSON with findings |
| `local-log-triage.md` | Parse logs for errors | JSON with findings |

Each outputs structured JSON with:
- `status`: completed/failed/escalate
- `findings[]`: severity, category, description, evidence
- `escalation`: { needed, reason, context }

### 5. Escalation Pipeline

When local model sets `escalation.needed: true`:
- Add to proactive queue for next wake cycle
- For critical findings: immediately invoke full Claude health-monitor agent

### 6. Integration Points

**Dream cycle (scripts/dream):**
- Run local maintenance at 2:55 AM (before 3 AM dream)
- Include findings in dream context if escalation needed

**Wake-light (scripts/wake-light):**
- Optional: run quick local health check first
- Only proceed with Claude if issues found (saves API calls)

**Scheduled (new launchd plist):**
- Run at 2:30 AM (pre-dream) and 1:30 PM (between wakes)

## Phase 1: Minimal Implementation (This PR)

Focus on proving the concept with one task: **health-check**

### Files to Create

| File | Purpose |
|------|---------|
| `scripts/local-maintenance` | Wrapper script (health-check only) |
| `.claude/agents/local-health-check.md` | Health check agent |
| `.claude/hooks/local-model-guardrail.sh` | Guardrail hook |
| `config/local-model-boundaries.json` | Boundary config |

### Files to Modify

| File | Change |
|------|--------|
| `.claude/settings.json` | Register guardrail hook |

### NOT in Phase 1 (Future)

- `local-drift-check.md` agent
- `local-log-triage.md` agent
- Dream cycle integration
- Wake-light integration
- Scheduled launchd plist

## Verification (Phase 1)

1. **Basic invocation**: Run `local-maintenance health-check`, verify Qwen3 executes and returns JSON
2. **Safety test**: From local session, attempt to write to identity.md - verify hook blocks it
3. **Health detection**: Stop Samara.app, run health-check, verify it reports "not running"
4. **Structured output**: Verify JSON output matches expected schema

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Local model writes to protected file | PreToolUse hook blocks; denylist at shell level |
| Local model sends message | osascript/message in bash denylist |
| Local model hallucinates | Structured output validation; manual escalation review |
| Ollama not running | Graceful skip with warning log |
