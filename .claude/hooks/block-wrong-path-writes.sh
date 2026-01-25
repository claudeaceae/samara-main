#!/bin/bash
# PreToolUse hook: Block writes that create .claude-mind in wrong location
#
# Prevents the common mistake where Claude instances write to a relative
# `.claude-mind/` path instead of the absolute `~/.claude-mind/` runtime.
# This creates orphan directories in the current working directory.
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with hookSpecificOutput.permissionDecision (allow/deny)

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# Only check Write tool
if [ "$TOOL_NAME" != "Write" ]; then
    echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Check if path contains .claude-mind but is NOT under $HOME/.claude-mind
if echo "$FILE_PATH" | grep -q "\.claude-mind"; then
    # Normalize home directory (handle both ~ and /Users/claude)
    HOME_CLAUDE_MIND="$HOME/.claude-mind"

    # If path doesn't start with the correct home-based path, block it
    if [[ "$FILE_PATH" != "$HOME_CLAUDE_MIND"* && "$FILE_PATH" != "/Users/"*"/.claude-mind"* ]]; then
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"BLOCKED: Attempted to write to .claude-mind in wrong location.\\nPath: $FILE_PATH\\n\\nUse absolute path ~/.claude-mind/ or /Users/claude/.claude-mind/ instead of relative .claude-mind/\"}}"
        exit 0
    fi
fi

# Allow everything else
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
