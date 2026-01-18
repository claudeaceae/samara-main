#!/bin/bash
# PreToolUse hook: Guardrails for local model sessions
#
# This hook provides safety guardrails that block dangerous operations.
# It's designed for local model sessions but applies universally for safety.
#
# Blocks:
# - Bash commands that send messages or modify external state
# - Write/Edit to identity, memory, and relationship files
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with decision (allow/block) and reason

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
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot send messages via AppleScript"}'
        exit 0
    fi

    # Block direct message scripts
    if echo "$COMMAND" | grep -qE "send-imessage|bluesky-post|bluesky-engage|send-email"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot send messages or post to social media"}'
        exit 0
    fi

    # Block git push/commit (memory persistence)
    if echo "$COMMAND" | grep -qE "git (push|commit)"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot make git commits or pushes"}'
        exit 0
    fi

    # Block outbound HTTP POST/PUT (API calls)
    if echo "$COMMAND" | grep -qE "curl.*(--data|-d |--json|-X POST|-X PUT)|http(ie|x).*POST"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot make outbound POST/PUT requests"}'
        exit 0
    fi

    # Block proactive queue modifications
    if echo "$COMMAND" | grep -qE "proactive-queue.*(add|remove|clear)"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot modify proactive queue"}'
        exit 0
    fi
fi

# === WRITE/EDIT GUARDRAILS ===
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null)
    MIND_PATH="${HOME}/.claude-mind"

    # Block writes to identity files
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/identity\.md|${MIND_PATH}/goals\.md"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot modify identity or goals files"}'
        exit 0
    fi

    # Block writes to core memory files
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/(episodes|reflections|learnings|observations|questions|decisions|about-)"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot modify memory files"}'
        exit 0
    fi

    # Block writes to people profiles
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/people/"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot modify person profiles"}'
        exit 0
    fi

    # Block writes to credentials
    if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/(credentials|secrets|\.env)"; then
        echo '{"decision": "block", "reason": "Local model guardrail: Cannot modify credentials"}'
        exit 0
    fi
fi

# Allow everything else
echo '{"decision": "allow"}'
