#!/bin/bash
# Stop hook: Check if iteration is in progress
#
# This hook runs when a Claude session ends. If an iteration is in progress
# and success criteria are not yet met, it reminds Claude to continue.
#
# Input: JSON with session info on stdin
# Output: JSON with {ok: boolean, message?: string}
#
# Note: We always return ok: true to allow exit, but provide guidance
# if iteration should continue. The next session will pick up where we left off.

INPUT=$(cat)
STATE_FILE="${HOME}/.claude-mind/state/iteration-state.json"

# Check if iteration state exists
if [ ! -f "$STATE_FILE" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Check iteration status
STATUS=$(jq -r '.status' "$STATE_FILE" 2>/dev/null || echo "unknown")

if [ "$STATUS" != "in_progress" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Iteration is in progress - gather info
GOAL=$(jq -r '.goal' "$STATE_FILE")
CURRENT=$(jq -r '.currentAttempt' "$STATE_FILE")
MAX=$(jq -r '.maxAttempts' "$STATE_FILE")
REMAINING=$((MAX - CURRENT))

# Get suggested next action
NEXT_APPROACH=$(jq -r '.attempts[-1].next_approach // empty' "$STATE_FILE")

# Build message
MESSAGE="Iteration in progress: $GOAL\n"
MESSAGE+="Attempts: $CURRENT/$MAX ($REMAINING remaining)\n"

if [ -n "$NEXT_APPROACH" ]; then
    MESSAGE+="\nSuggested next: $NEXT_APPROACH"
fi

MESSAGE+="\n\nUse '/iterate' to continue or 'iterate-complete' to finish."

# Return with reminder message
# Note: ok: true allows exit; message reminds about iteration
echo "{\"ok\": true, \"message\": \"$MESSAGE\"}"
