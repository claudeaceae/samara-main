#!/bin/bash
# PreToolUse hook: Archive existing plan files before overwrite
#
# When a Write or Edit targets ~/.claude/plans/, archive the existing file
# with a timestamp before allowing the write. This preserves plan history
# for decision archaeology and intent preservation.
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with decision (allow) - we archive, never block
#
# Archive location: ~/.claude/plans/archive/
# Archive naming: {original-name}-{YYYY-MM-DD-HHMMSS}.md

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Only check Write and Edit tools
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Only care about files in ~/.claude/plans/
PLANS_DIR="$HOME/.claude/plans"
if [[ ! "$FILE_PATH" == "$PLANS_DIR"/* ]]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Don't archive files in the archive directory itself
if [[ "$FILE_PATH" == "$PLANS_DIR/archive/"* ]]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# If file doesn't exist yet, nothing to archive
if [ ! -f "$FILE_PATH" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Archive the existing file
ARCHIVE_DIR="$PLANS_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

BASENAME=$(basename "$FILE_PATH" .md)
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
ARCHIVE_PATH="$ARCHIVE_DIR/${BASENAME}-${TIMESTAMP}.md"

# Copy with metadata preservation
cp -p "$FILE_PATH" "$ARCHIVE_PATH"

if [ $? -eq 0 ]; then
    # Add archive note to the archived file
    echo "" >> "$ARCHIVE_PATH"
    echo "---" >> "$ARCHIVE_PATH"
    echo "*Archived at $(date '+%Y-%m-%d %H:%M:%S') before overwrite*" >> "$ARCHIVE_PATH"

    # Build JSON with jq to handle special characters in paths
    jq -n --arg path "$ARCHIVE_PATH" '{decision: "allow", message: ("Archived previous version to " + $path)}' 2>/dev/null || echo '{"decision": "allow"}'
else
    # Archive failed, but don't block - just warn
    jq -n --arg path "$FILE_PATH" '{decision: "allow", message: ("Warning: Failed to archive " + $path + " before overwrite")}' 2>/dev/null || echo '{"decision": "allow"}'
fi
