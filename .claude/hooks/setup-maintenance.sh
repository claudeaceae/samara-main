#!/bin/bash
# Setup hook - runs on `claude --init` or `claude --maintenance`
# Performs organism health checks and maintenance tasks

set -e

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"

# Parse hook input (JSON on stdin)
INPUT=$(cat)

# Check if this is a maintenance context
ARGS=$(echo "$INPUT" | jq -r '.args // []' 2>/dev/null)

# Create output JSON (SessionStart format per docs)
output_context() {
    local context="$1"
    # Use jq to properly escape the context string
    echo "$context" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null || echo '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "Health check completed"}}'
}

# Run maintenance checks
run_checks() {
    local issues=""

    # 1. Check for system drift
    if [ -f "$MIND_PATH/system/bin/sync-organism" ]; then
        if ! "$MIND_PATH/system/bin/sync-organism" --check >/dev/null 2>&1; then
            issues="$issues\n- System drift detected (run sync-organism to fix)"
        fi
    fi

    # 2. Check symlinks
    local broken_links=0
    for link in "$MIND_PATH/system/bin" "$MIND_PATH/.claude" "$MIND_PATH/system/instructions"; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            issues="$issues\n- Broken symlink: $link"
            broken_links=$((broken_links + 1))
        fi
    done

    # 3. Check launchd services
    local loaded_jobs=$(launchctl list 2>/dev/null | grep -c "com.claude" || echo 0)
    if [ "$loaded_jobs" -lt 4 ]; then
        issues="$issues\n- Only $loaded_jobs launchd jobs loaded (expected 4+)"
    fi

    # 4. Check Samara.app running
    if ! pgrep -x Samara >/dev/null 2>&1; then
        issues="$issues\n- Samara.app not running"
    fi

    # 5. Check stale lock file
    if [ -f "$MIND_PATH/state/locks/system-cli.lock" ]; then
        local lock_pid=$(cat "$MIND_PATH/state/locks/system-cli.lock" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pid',''))" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            issues="$issues\n- Stale lock file from dead process $lock_pid"
        fi
    fi

    # Output results
    if [ -n "$issues" ]; then
        echo -e "Maintenance issues found:$issues" | sed 's/\\n/\n/g'
    else
        echo "All systems healthy. No maintenance issues found."
    fi
}

# Run checks and provide context
RESULT=$(run_checks)
output_context "$RESULT"
