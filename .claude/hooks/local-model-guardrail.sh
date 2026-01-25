#!/bin/bash
# PreToolUse hook: Guardrails for local model sessions
#
# This hook provides safety guardrails that block dangerous operations.
# These guardrails ONLY apply when running on a local model (Ollama).
# Full Claude (Opus/Sonnet/Haiku via API) is trusted and unrestricted.
#
# Detection: Local models use ANTHROPIC_BASE_URL pointing to localhost
#
# Blocks (local models only):
# - Bash commands that send messages or modify external state
# - Write/Edit to identity, memory, and relationship files
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with hookSpecificOutput.permissionDecision (allow/deny)

# Check if running on a local model (Ollama)
# Local models use ANTHROPIC_BASE_URL=http://localhost:11434 or similar
if [ -z "$ANTHROPIC_BASE_URL" ] || ! echo "$ANTHROPIC_BASE_URL" | grep -qE "localhost|127\.0\.0\.1"; then
    # Not a local model - allow everything (full Claude is trusted)
    cat > /dev/null  # consume stdin
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

# === LOCAL MODEL GUARDRAILS BELOW ===
# Only reached if ANTHROPIC_BASE_URL points to localhost

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}' 2>/dev/null)

# Load boundaries config if it exists
CONFIG_FILE="${HOME}/.claude-mind/config/local-model-boundaries.json"

# === BASH COMMAND GUARDRAILS ===
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null)

    # Block messaging commands (voice/communication)
    if echo "$COMMAND" | grep -qE "osascript.*send|osascript.*message|osascript.*mail"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot send messages via AppleScript"}}'
        exit 0
    fi

    # Block direct message scripts
    if echo "$COMMAND" | grep -qE "send-imessage|bluesky-post|bluesky-engage|send-email"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot send messages or post to social media"}}'
        exit 0
    fi

    # Block git push/commit (memory persistence)
    if echo "$COMMAND" | grep -qE "git (push|commit)"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot make git commits or pushes"}}'
        exit 0
    fi

    # Block outbound HTTP POST/PUT (API calls)
    if echo "$COMMAND" | grep -qE "curl.*(--data|-d |--json|-X POST|-X PUT)|http(ie|x).*POST"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot make outbound POST/PUT requests"}}'
        exit 0
    fi

    # Block proactive queue modifications
    if echo "$COMMAND" | grep -qE "proactive-queue.*(add|remove|clear)"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify proactive queue"}}'
        exit 0
    fi
fi

# === WRITE/EDIT GUARDRAILS ===
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null)
    MIND_PATH="${HOME}/.claude-mind"

    # Block writes to identity files
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/self/identity\.md|${MIND_PATH}/self/goals\.md"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify identity or goals files"}}'
        exit 0
    fi

    # Block writes to core memory files
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/(episodes|reflections|learnings|observations|questions|decisions|about-)"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify memory files"}}'
        exit 0
    fi

    # Block writes to people profiles
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/people/"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify person profiles"}}'
        exit 0
    fi

    # Block writes to credentials
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/self/credentials|${MIND_PATH}/(secrets|\.env)"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify credentials"}}'
        exit 0
    fi
fi

# Allow everything else
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
