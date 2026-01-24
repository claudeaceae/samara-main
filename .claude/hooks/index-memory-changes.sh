#!/bin/bash
# PostToolUse hook: Trigger incremental memory indexing
#
# When memory files are modified, trigger incremental index updates
# to eliminate the 6-18 hour lag before new content is searchable.
#
# Input: JSON with tool_name, tool_input, tool_response on stdin
# Output: JSON allowing continuation, with optional additionalContext

# Note: NOT using set -e to ensure we always output valid JSON

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Only process Write and Edit tools
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Check if file is in memory directories
MEMORY_DIR="$MIND_PATH/memory"
PEOPLE_DIR="$MEMORY_DIR/people"

# Resolve any symlinks in paths for comparison
REAL_FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
REAL_MEMORY_DIR=$(realpath "$MEMORY_DIR" 2>/dev/null || echo "$MEMORY_DIR")
REAL_PEOPLE_DIR=$(realpath "$PEOPLE_DIR" 2>/dev/null || echo "$PEOPLE_DIR")

INDEX_TRIGGERED=""

# Check if file is in memory directory
if [[ "$REAL_FILE_PATH" == "$REAL_MEMORY_DIR"/* ]]; then
    # Trigger FTS5 incremental update (background, non-blocking)
    if [ -x "$MIND_PATH/system/bin/memory-index" ]; then
        # memory-index sync just updates the index for changed files
        nohup "$MIND_PATH/system/bin/memory-index" sync "$FILE_PATH" >> "$MIND_PATH/system/logs/memory-index.log" 2>&1 &
        INDEX_TRIGGERED+="FTS5 "
    fi

    # If it's a person profile, also trigger Chroma update
    if [[ "$REAL_FILE_PATH" == "$REAL_PEOPLE_DIR"/* ]] && [[ "$FILE_PATH" == *.md ]]; then
        # Use chroma helper's incremental indexing
        CHROMA_HELPER="$HOME/Developer/samara-main/lib/chroma_helper.py"
        if [ -f "$CHROMA_HELPER" ]; then
            nohup python3 "$CHROMA_HELPER" index-single "$FILE_PATH" >> "$MIND_PATH/system/logs/chroma-index.log" 2>&1 &
            INDEX_TRIGGERED+="Chroma "
        fi
    fi
fi

# Provide feedback if indexing was triggered
if [ -n "$INDEX_TRIGGERED" ]; then
    BASENAME=$(basename "$FILE_PATH")
    # Build entire JSON with jq to avoid shell escaping issues
    jq -n --arg msg "Memory index updated: $BASENAME ($INDEX_TRIGGERED)" '{ok: true, hookSpecificOutput: {additionalContext: $msg}}' 2>/dev/null || echo '{"ok": true}'
else
    echo '{"ok": true}'
fi
