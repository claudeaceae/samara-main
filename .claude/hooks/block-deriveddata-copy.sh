#!/bin/bash
# PreToolUse hook: Block dangerous Samara.app copies from DerivedData
#
# This hook prevents the mistake that caused FDA revocation on 2026-01-04:
# Copying a Debug build from DerivedData instead of using update-samara script.
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with decision (allow/block) and reason

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Only check Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Pattern 1: Copying from DerivedData to Applications/Samara
if echo "$COMMAND" | grep -qE "cp.*DerivedData.*Samara.*Applications|cp.*DerivedData.*Applications.*Samara"; then
    echo '{"decision": "block", "reason": "BLOCKED: Never copy Samara.app from DerivedData! This uses wrong signing certificate and breaks FDA. Use ~/.claude-mind/bin/update-samara instead."}'
    exit 0
fi

# Pattern 2: Copying any Samara.app to Applications (unless from /tmp/SamaraExport which is the correct path)
if echo "$COMMAND" | grep -qE "cp.*Samara\.app.*/Applications" && ! echo "$COMMAND" | grep -q "SamaraExport"; then
    # Check if it's from the approved path
    if ! echo "$COMMAND" | grep -qE "/tmp/SamaraExport/Samara\.app"; then
        echo '{"decision": "block", "reason": "BLOCKED: Manual copy of Samara.app to /Applications is forbidden. Use ~/.claude-mind/bin/update-samara which handles signing and notarization correctly."}'
        exit 0
    fi
fi

# Pattern 3: Debug build deployment
if echo "$COMMAND" | grep -qE "xcodebuild.*Debug.*Samara" && echo "$COMMAND" | grep -q "build"; then
    if ! echo "$COMMAND" | grep -q "test"; then
        echo '{"decision": "block", "reason": "BLOCKED: Debug builds should not be deployed. Use ~/.claude-mind/bin/update-samara for proper Release + notarized builds."}'
        exit 0
    fi
fi

# Allow everything else
echo '{"decision": "allow"}'
