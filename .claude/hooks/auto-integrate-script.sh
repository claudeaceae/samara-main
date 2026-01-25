#!/bin/bash
# PostToolUse hook: Auto-integrate new scripts
#
# When a script is written to the scripts/ directory:
# 1. Create symlink in ~/.claude-mind/system/bin/
# 2. Run basic syntax check
# 3. Append entry to capabilities changelog
#
# Input: JSON with tool_name, tool_input, tool_response on stdin
# Output: JSON with optional additionalContext

# Note: NOT using set -e to ensure we always output valid JSON

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
REPO_PATH="$HOME/Developer/samara-main"
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Only process Write tool
if [ "$TOOL_NAME" != "Write" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Check if file is in scripts directory
SCRIPTS_DIR="$REPO_PATH/scripts"
if [[ "$FILE_PATH" != "$SCRIPTS_DIR"/* ]]; then
    echo '{"ok": true}'
    exit 0
fi

SCRIPT_NAME=$(basename "$FILE_PATH")
SYMLINK_PATH="$MIND_PATH/system/bin/$SCRIPT_NAME"
MESSAGES=""

# 1. Create symlink if doesn't exist
if [ ! -L "$SYMLINK_PATH" ] && [ ! -f "$SYMLINK_PATH" ]; then
    ln -s "$FILE_PATH" "$SYMLINK_PATH"
    MESSAGES+="Symlinked to $SYMLINK_PATH. "
elif [ -L "$SYMLINK_PATH" ]; then
    # Symlink exists, verify it points to the right place
    CURRENT_TARGET=$(readlink "$SYMLINK_PATH")
    if [ "$CURRENT_TARGET" != "$FILE_PATH" ]; then
        rm "$SYMLINK_PATH"
        ln -s "$FILE_PATH" "$SYMLINK_PATH"
        MESSAGES+="Updated symlink. "
    fi
fi

# 2. Run basic syntax check (if shellcheck available)
if command -v shellcheck &>/dev/null; then
    if ! shellcheck -S error "$FILE_PATH" >/dev/null 2>&1; then
        MESSAGES+="[WARN] shellcheck found issues. "
    fi
else
    # Fallback: basic bash syntax check
    if head -1 "$FILE_PATH" | grep -q "^#!/.*bash"; then
        if ! bash -n "$FILE_PATH" 2>/dev/null; then
            MESSAGES+="[WARN] Bash syntax error detected. "
        fi
    fi
fi

# 3. Append to capabilities changelog
CHANGELOG="$MIND_PATH/self/capabilities/changelog.md"
if [ -f "$CHANGELOG" ]; then
    TODAY=$(date +%Y-%m-%d)
    # Check if we already logged this script today
    if ! grep -q "$TODAY.*$SCRIPT_NAME" "$CHANGELOG" 2>/dev/null; then
        echo "" >> "$CHANGELOG"
        echo "- $TODAY: Added script \`$SCRIPT_NAME\`" >> "$CHANGELOG"
        MESSAGES+="Logged to changelog. "
    fi
fi

# Output result
if [ -n "$MESSAGES" ]; then
    # Build entire JSON with jq to avoid shell escaping issues
    jq -n --arg msg "Script auto-integrated: $MESSAGES" '{ok: true, hookSpecificOutput: {additionalContext: $msg}}' 2>/dev/null || echo '{"ok": true}'
else
    echo '{"ok": true}'
fi
