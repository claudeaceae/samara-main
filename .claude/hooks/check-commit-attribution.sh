#!/bin/bash
# PostToolUse hook: Check for commit co-authorship
#
# Ensures git commits include the Co-Authored-By line as documented in CLAUDE.md.
# Warns (doesn't block) if attribution is missing.
#
# Input: JSON with tool_name, tool_input, tool_response on stdin
# Output: JSON with optional additionalContext warning

# Note: NOT using set -e to ensure we always output valid JSON

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // ""')

# Only check Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE "git commit"; then
    echo '{"ok": true}'
    exit 0
fi

# Check if commit succeeded (look for success indicators in response)
if echo "$RESPONSE" | grep -qiE "nothing to commit|no changes|error:|fatal:"; then
    echo '{"ok": true}'
    exit 0
fi

# Check if Co-Authored-By was included
if echo "$COMMAND" | grep -qi "Co-Authored-By"; then
    echo '{"ok": true}'
    exit 0
fi

# Commit succeeded but no co-authorship - warn
WARNING="Commit created without Co-Authored-By attribution. Per CLAUDE.md, commits should include:

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>

Consider amending: git commit --amend (if not yet pushed)"

# Escape for JSON
WARNING_ESCAPED=$(echo "$WARNING" | jq -Rs .)

echo "{\"ok\": true, \"hookSpecificOutput\": {\"additionalContext\": $WARNING_ESCAPED}}"
