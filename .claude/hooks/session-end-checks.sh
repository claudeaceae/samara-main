#!/bin/bash
# Stop hook: Consolidated session-end checks
#
# Combines multiple end-of-session checks into one efficient hook:
# 1. System drift detection (repo vs runtime)
# 2. Active iteration reminders
# 3. New capability detection
#
# Priority ordering: iterations (urgent) → drift (important) → capabilities (informational)
#
# Input: JSON with stop_hook_active on stdin
# Output: JSON with {ok: boolean, decision?: string, reason?: string, message?: string}

# Note: NOT using set -e because grep/jq failures are expected in some paths

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
REPO_DIR="$HOME/Developer/samara-main"
INPUT=$(cat)

# Check if stop hook is already active (prevent infinite loops)
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_ACTIVE" = "true" ]; then
    echo '{"ok": true}'
    exit 0
fi

MESSAGES=""
BLOCK_REASON=""

# === 1. CHECK ACTIVE ITERATIONS (Highest Priority) ===
ITERATION_STATE="$MIND_PATH/state/iteration-state.json"
if [ -f "$ITERATION_STATE" ]; then
    STATUS=$(jq -r '.status // "unknown"' "$ITERATION_STATE" 2>/dev/null)
    if [ "$STATUS" = "in_progress" ]; then
        GOAL=$(jq -r '.goal // "unknown goal"' "$ITERATION_STATE")
        CURRENT=$(jq -r '.currentAttempt // 0' "$ITERATION_STATE")
        MAX=$(jq -r '.maxAttempts // 10' "$ITERATION_STATE")
        REMAINING=$((MAX - CURRENT))
        NEXT_APPROACH=$(jq -r '.attempts[-1].next_approach // ""' "$ITERATION_STATE")

        BLOCK_REASON="Iteration in progress: $GOAL\n"
        BLOCK_REASON+="Attempts: $CURRENT/$MAX ($REMAINING remaining)\n"
        if [ -n "$NEXT_APPROACH" ] && [ "$NEXT_APPROACH" != "null" ]; then
            BLOCK_REASON+="Suggested next: $NEXT_APPROACH\n"
        fi
        BLOCK_REASON+="\nUse '/iterate' to continue or 'iterate-complete' to finish."
    fi
fi

# === 2. CHECK SYSTEM DRIFT (Important) ===
if [ -x "$MIND_PATH/bin/sync-organism" ]; then
    if ! "$MIND_PATH/bin/sync-organism" --check >/dev/null 2>&1; then
        DRIFT_SUMMARY=$("$MIND_PATH/bin/sync-organism" 2>&1 | grep -E "^(Repo scripts|Runtime scripts|Only in|Differ|Total drift)" | head -5)
        if [ -n "$DRIFT_SUMMARY" ]; then
            MESSAGES+="⚠️ System drift detected:\n$DRIFT_SUMMARY\n\nConsider running /sync before next session.\n\n"
        fi
    fi
fi

# === 3. CHECK NEW CAPABILITIES (Informational) ===
cd "$REPO_DIR" 2>/dev/null || true

NEW_CAPABILITIES=""
INVENTORY="$MIND_PATH/capabilities/inventory.md"

for dir in scripts .claude/skills services; do
    if [ -d "$dir" ]; then
        untracked=$(git ls-files --others --exclude-standard "$dir" 2>/dev/null)
        if [ -n "$untracked" ]; then
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                basename=$(basename "$file")
                if ! grep -q "$basename" "$INVENTORY" 2>/dev/null; then
                    NEW_CAPABILITIES+="  - $file\n"
                fi
            done <<< "$untracked"
        fi
    fi
done

if [ -n "$NEW_CAPABILITIES" ]; then
    MESSAGES+="📦 Undocumented capabilities:\n$NEW_CAPABILITIES\nConsider documenting in inventory.md.\n"
fi

# === 4. CHECK NEW INFRASTRUCTURE PURPOSE (Learning from Dec 23) ===
# "I can build infrastructure without understanding what it's for"
# Check if new scripts were created this session without changelog entries

CHANGELOG="$MIND_PATH/capabilities/changelog.md"
TODAY=$(date +%Y-%m-%d)

# Get scripts modified today (created or changed)
NEW_SCRIPTS_TODAY=""
if [ -d "$REPO_DIR/scripts" ]; then
    for script in "$REPO_DIR/scripts"/*; do
        [ -f "$script" ] || continue
        SCRIPT_DATE=$(stat -f %Sm -t %Y-%m-%d "$script" 2>/dev/null)
        if [ "$SCRIPT_DATE" = "$TODAY" ]; then
            SCRIPT_NAME=$(basename "$script")
            # Check if it's documented in changelog for today
            if ! grep -q "$TODAY.*$SCRIPT_NAME" "$CHANGELOG" 2>/dev/null; then
                NEW_SCRIPTS_TODAY+="  - $SCRIPT_NAME\n"
            fi
        fi
    done
fi

if [ -n "$NEW_SCRIPTS_TODAY" ]; then
    MESSAGES+="🔧 New infrastructure created today:\n$NEW_SCRIPTS_TODAY"
    MESSAGES+="Consider documenting purpose in changelog.md:\n"
    MESSAGES+="\"What should this feel like when it works?\"\n\n"
fi

# === BUILD OUTPUT ===

# If iteration is blocking, return block decision
if [ -n "$BLOCK_REASON" ]; then
    # Escape for JSON
    BLOCK_ESCAPED=$(echo -e "$BLOCK_REASON" | jq -Rs .)

    # Add other messages as context
    if [ -n "$MESSAGES" ]; then
        MESSAGES_ESCAPED=$(echo -e "$MESSAGES" | jq -Rs .)
        echo "{\"decision\": \"block\", \"reason\": $BLOCK_ESCAPED, \"message\": $MESSAGES_ESCAPED}"
    else
        echo "{\"decision\": \"block\", \"reason\": $BLOCK_ESCAPED}"
    fi
    exit 0
fi

# No blocking, just informational messages
if [ -n "$MESSAGES" ]; then
    MESSAGES_ESCAPED=$(echo -e "$MESSAGES" | jq -Rs .)
    echo "{\"ok\": true, \"message\": $MESSAGES_ESCAPED}"
else
    echo '{"ok": true}'
fi
