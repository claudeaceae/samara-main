#!/bin/bash
# PreToolUse hook: Check for autonomous media capture attempts
#
# Blocks unprompted privacy-sensitive actions:
# - Webcam captures (/look, imagesnap)
# - Screenshots
# - Location-triggered photos
#
# Based on user correction: "Should have just said welcome back without the photo"
#
# Input: JSON with tool_name, tool_input on stdin
# Output: JSON with decision (allow/block)

# Note: NOT using set -e to ensure we always output valid JSON

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only check Bash and Skill tools
if [ "$TOOL_NAME" != "Bash" ] && [ "$TOOL_NAME" != "Skill" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Check for media capture patterns
IS_MEDIA_CAPTURE=false
CAPTURE_TYPE=""

# Webcam/camera commands
if echo "$COMMAND" | grep -qiE "imagesnap|ffmpeg.*video|avfoundation|/look"; then
    IS_MEDIA_CAPTURE=true
    CAPTURE_TYPE="webcam"
fi

# Screenshot commands
if echo "$COMMAND" | grep -qiE "screencapture|screenshot"; then
    IS_MEDIA_CAPTURE=true
    CAPTURE_TYPE="screenshot"
fi

# Skill invocation check
if [ "$TOOL_NAME" = "Skill" ]; then
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""')
    if [ "$SKILL_NAME" = "look" ]; then
        IS_MEDIA_CAPTURE=true
        CAPTURE_TYPE="webcam"
    fi
fi

if [ "$IS_MEDIA_CAPTURE" = false ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Check if this is in response to an explicit user request
# We check the session context for recent user messages containing photo/camera keywords
# For now, we use a simple heuristic: check if there's a marker file indicating explicit request

EXPLICIT_REQUEST_MARKER="$MIND_PATH/state/.media-request-explicit"

# If marker exists and is recent (within last 5 minutes), allow
if [ -f "$EXPLICIT_REQUEST_MARKER" ]; then
    MARKER_AGE=$(($(date +%s) - $(stat -f %m "$EXPLICIT_REQUEST_MARKER" 2>/dev/null || echo 0)))
    if [ "$MARKER_AGE" -lt 300 ]; then
        echo '{"decision": "allow"}'
        exit 0
    fi
fi

# Check if the current invocation context suggests explicit request
# This is a heuristic - check for keywords in recent prompt context
# For now, we'll be conservative and block autonomous captures

# Log the blocked attempt
EPISODE_FILE="$MIND_PATH/memory/episodes/$(date +%Y-%m-%d).md"
if [ -f "$EPISODE_FILE" ]; then
    echo "" >> "$EPISODE_FILE"
    echo "- $(date '+%H:%M') [Hook] Blocked autonomous $CAPTURE_TYPE capture (ask first)" >> "$EPISODE_FILE"
fi

echo "{\"decision\": \"block\", \"reason\": \"Privacy-sensitive action ($CAPTURE_TYPE capture) requires explicit user request. Ask first before capturing photos or screenshots autonomously.\"}"
