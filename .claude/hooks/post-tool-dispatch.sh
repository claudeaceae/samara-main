#!/bin/bash
# Unified PostToolUse dispatcher — replaces 3 separate hook scripts
#
# Consolidates: index-memory-changes, auto-integrate-script, check-commit-attribution
#
# One fork instead of 2-3 per tool call.
#
# Input: JSON with tool_name, tool_input, tool_response on stdin
# Output: JSON with optional additionalContext

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
REPO_PATH="$HOME/Developer/samara-main"
OK='{"ok": true}'

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$TOOL_NAME" in

Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    MESSAGES=""

    # --- Index memory changes ---
    MEMORY_DIR="$MIND_PATH/memory"
    REAL_FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    REAL_MEMORY_DIR=$(realpath "$MEMORY_DIR" 2>/dev/null || echo "$MEMORY_DIR")

    if [[ "$REAL_FILE_PATH" == "$REAL_MEMORY_DIR"/* ]]; then
        if [ -x "$MIND_PATH/system/bin/memory-index" ]; then
            nohup "$MIND_PATH/system/bin/memory-index" sync "$FILE_PATH" >> "$MIND_PATH/system/logs/memory-index.log" 2>&1 &
            MESSAGES+="FTS5 indexed. "
        fi
        REAL_PEOPLE_DIR=$(realpath "$MEMORY_DIR/people" 2>/dev/null || echo "$MEMORY_DIR/people")
        if [[ "$REAL_FILE_PATH" == "$REAL_PEOPLE_DIR"/* ]] && [[ "$FILE_PATH" == *.md ]]; then
            CHROMA_HELPER="$REPO_PATH/lib/chroma_helper.py"
            if [ -f "$CHROMA_HELPER" ]; then
                nohup python3 "$CHROMA_HELPER" index-single "$FILE_PATH" >> "$MIND_PATH/system/logs/chroma-index.log" 2>&1 &
                MESSAGES+="Chroma indexed. "
            fi
        fi
    fi

    # --- Auto-integrate script ---
    SCRIPTS_DIR="$REPO_PATH/scripts"
    if [[ "$FILE_PATH" == "$SCRIPTS_DIR"/* ]]; then
        SCRIPT_NAME=$(basename "$FILE_PATH")
        SYMLINK_PATH="$MIND_PATH/system/bin/$SCRIPT_NAME"

        if [ ! -L "$SYMLINK_PATH" ] && [ ! -f "$SYMLINK_PATH" ]; then
            ln -s "$FILE_PATH" "$SYMLINK_PATH"
            MESSAGES+="Symlinked $SCRIPT_NAME. "
        elif [ -L "$SYMLINK_PATH" ]; then
            CURRENT_TARGET=$(readlink "$SYMLINK_PATH")
            if [ "$CURRENT_TARGET" != "$FILE_PATH" ]; then
                rm "$SYMLINK_PATH"
                ln -s "$FILE_PATH" "$SYMLINK_PATH"
                MESSAGES+="Updated symlink. "
            fi
        fi

        if command -v shellcheck &>/dev/null; then
            if ! shellcheck -S error "$FILE_PATH" >/dev/null 2>&1; then
                MESSAGES+="[WARN] shellcheck found issues. "
            fi
        else
            if head -1 "$FILE_PATH" | grep -q "^#!/.*bash"; then
                if ! bash -n "$FILE_PATH" 2>/dev/null; then
                    MESSAGES+="[WARN] Bash syntax error. "
                fi
            fi
        fi

        CHANGELOG="$MIND_PATH/self/changelog.md"
        if [ -f "$CHANGELOG" ]; then
            TODAY=$(date +%Y-%m-%d)
            if ! grep -q "$TODAY.*$SCRIPT_NAME" "$CHANGELOG" 2>/dev/null; then
                echo -e "\n- $TODAY: Added script \`$SCRIPT_NAME\`" >> "$CHANGELOG"
                MESSAGES+="Logged to changelog. "
            fi
        fi
    fi

    if [ -n "$MESSAGES" ]; then
        jq -n --arg msg "$MESSAGES" '{ok: true, hookSpecificOutput: {additionalContext: $msg}}' 2>/dev/null || echo "$OK"
    else
        echo "$OK"
    fi
    ;;

Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

    # --- Index memory changes (Edit only — no script integration) ---
    MEMORY_DIR="$MIND_PATH/memory"
    REAL_FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    REAL_MEMORY_DIR=$(realpath "$MEMORY_DIR" 2>/dev/null || echo "$MEMORY_DIR")

    if [[ "$REAL_FILE_PATH" == "$REAL_MEMORY_DIR"/* ]]; then
        if [ -x "$MIND_PATH/system/bin/memory-index" ]; then
            nohup "$MIND_PATH/system/bin/memory-index" sync "$FILE_PATH" >> "$MIND_PATH/system/logs/memory-index.log" 2>&1 &
        fi
        REAL_PEOPLE_DIR=$(realpath "$MEMORY_DIR/people" 2>/dev/null || echo "$MEMORY_DIR/people")
        if [[ "$REAL_FILE_PATH" == "$REAL_PEOPLE_DIR"/* ]] && [[ "$FILE_PATH" == *.md ]]; then
            CHROMA_HELPER="$REPO_PATH/lib/chroma_helper.py"
            if [ -f "$CHROMA_HELPER" ]; then
                nohup python3 "$CHROMA_HELPER" index-single "$FILE_PATH" >> "$MIND_PATH/system/logs/chroma-index.log" 2>&1 &
            fi
        fi
        BASENAME=$(basename "$FILE_PATH")
        jq -n --arg msg "Memory index updated: $BASENAME" '{ok: true, hookSpecificOutput: {additionalContext: $msg}}' 2>/dev/null || echo "$OK"
    else
        echo "$OK"
    fi
    ;;

Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null)

    # --- Check commit attribution ---
    if echo "$COMMAND" | grep -qE "git commit"; then
        # Skip if commit failed
        if echo "$RESPONSE" | grep -qiE "nothing to commit|no changes|error:|fatal:"; then
            echo "$OK"; exit 0
        fi
        # Check if Co-Authored-By was included
        if ! echo "$COMMAND" | grep -qi "Co-Authored-By"; then
            WARNING="Commit created without Co-Authored-By attribution. Per CLAUDE.md, commits should include:

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

Consider amending: git commit --amend (if not yet pushed)"
            echo "$WARNING" | jq -Rs '{ok: true, hookSpecificOutput: {additionalContext: .}}' 2>/dev/null || echo "$OK"
            exit 0
        fi
    fi

    echo "$OK"
    ;;

*)
    echo "$OK"
    ;;
esac
