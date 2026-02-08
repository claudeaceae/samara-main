#!/bin/bash
# Unified PreToolUse dispatcher — replaces 5 separate hook scripts
#
# Consolidates: block-wrong-path-writes, archive-plan-before-write,
#               local-model-guardrail, block-deriveddata-copy, check-autonomous-media
#
# One fork instead of 2-3 per tool call.
#
# Input: JSON with tool_name and tool_input on stdin
# Output: JSON with hookSpecificOutput.permissionDecision

ALLOW='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'

# === Local model guardrail (early exit for non-local) ===
if [ -n "$ANTHROPIC_BASE_URL" ] && echo "$ANTHROPIC_BASE_URL" | grep -qE "localhost|127\.0\.0\.1"; then
    IS_LOCAL=true
else
    IS_LOCAL=false
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

case "$TOOL_NAME" in

Write|Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

    # --- Local model guardrail: block sensitive writes ---
    if [ "$IS_LOCAL" = true ]; then
        MIND_PATH="${HOME}/.claude-mind"
        if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/self/identity\.md|${MIND_PATH}/self/goals\.md"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify identity or goals files"}}'
            exit 0
        fi
        if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/(episodes|reflections|learnings|observations|questions|decisions|about-)"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify memory files"}}'
            exit 0
        fi
        if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/memory/people/"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify person profiles"}}'
            exit 0
        fi
        if echo "$FILE_PATH" | grep -qE "${MIND_PATH}/(secrets|\.env)"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify secrets"}}'
            exit 0
        fi
    fi

    # --- Block wrong-path writes (Write only) ---
    if [ "$TOOL_NAME" = "Write" ]; then
        # Block writes to runtime sessions/ (wrong location)
        if [[ "$FILE_PATH" == "sessions/"* || "$FILE_PATH" == "./sessions/"* ]] || \
           [[ "$FILE_PATH" == "$HOME/.claude-mind/sessions"* ]] || \
           [[ "$FILE_PATH" == "/Users/"*"/.claude-mind/sessions"* ]]; then
            echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"BLOCKED: Session state does not live in ~/.claude-mind/sessions.\\nUse ~/.claude-mind/memory/sessions for session JSON, or ~/.claude-mind/state/handoffs for handoff docs.\\nPath: $FILE_PATH\"}}"
            exit 0
        fi

        # Block relative .claude-mind paths
        if echo "$FILE_PATH" | grep -q "\.claude-mind"; then
            HOME_CLAUDE_MIND="$HOME/.claude-mind"
            if [[ "$FILE_PATH" != "$HOME_CLAUDE_MIND"* && "$FILE_PATH" != "/Users/"*"/.claude-mind"* ]]; then
                echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"BLOCKED: Attempted to write to .claude-mind in wrong location.\\nPath: $FILE_PATH\\n\\nUse absolute path ~/.claude-mind/ or /Users/claude/.claude-mind/ instead of relative .claude-mind/\"}}"
                exit 0
            fi
        fi
    fi

    # --- Archive plan before write ---
    PLANS_DIR="$HOME/.claude/plans"
    if [[ "$FILE_PATH" == "$PLANS_DIR"/* && "$FILE_PATH" != "$PLANS_DIR/archive/"* ]]; then
        if [ -f "$FILE_PATH" ]; then
            ARCHIVE_DIR="$PLANS_DIR/archive"
            mkdir -p "$ARCHIVE_DIR"
            BASENAME=$(basename "$FILE_PATH" .md)
            TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
            ARCHIVE_PATH="$ARCHIVE_DIR/${BASENAME}-${TIMESTAMP}.md"
            if cp -p "$FILE_PATH" "$ARCHIVE_PATH" 2>/dev/null; then
                echo "" >> "$ARCHIVE_PATH"
                echo "---" >> "$ARCHIVE_PATH"
                echo "*Archived at $(date '+%Y-%m-%d %H:%M:%S') before overwrite*" >> "$ARCHIVE_PATH"
                jq -n --arg path "$ARCHIVE_PATH" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", additionalContext: ("Archived previous version to " + $path)}}' 2>/dev/null || echo "$ALLOW"
                exit 0
            fi
        fi
    fi

    echo "$ALLOW"
    ;;

Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

    # --- Local model guardrail: block dangerous commands ---
    if [ "$IS_LOCAL" = true ]; then
        if echo "$COMMAND" | grep -qE "osascript.*send|osascript.*message|osascript.*mail"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot send messages via AppleScript"}}'
            exit 0
        fi
        if echo "$COMMAND" | grep -qE "send-imessage|bluesky-post|bluesky-engage|send-email"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot send messages or post to social media"}}'
            exit 0
        fi
        if echo "$COMMAND" | grep -qE "git (push|commit)"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot make git commits or pushes"}}'
            exit 0
        fi
        if echo "$COMMAND" | grep -qE "curl.*(--data|-d |--json|-X POST|-X PUT)|http(ie|x).*POST"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot make outbound POST/PUT requests"}}'
            exit 0
        fi
        if echo "$COMMAND" | grep -qE "proactive-queue.*(add|remove|clear)"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot modify proactive queue"}}'
            exit 0
        fi
    fi

    # --- Block DerivedData copies ---
    if echo "$COMMAND" | grep -qE "cp.*DerivedData.*Samara.*Applications|cp.*DerivedData.*Applications.*Samara"; then
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "BLOCKED: Never copy Samara.app from DerivedData! This uses wrong signing certificate and breaks FDA. Use ~/.claude-mind/system/bin/update-samara instead."}}'
        exit 0
    fi
    if echo "$COMMAND" | grep -qE "cp.*Samara\.app.*/Applications" && ! echo "$COMMAND" | grep -q "SamaraExport"; then
        if ! echo "$COMMAND" | grep -qE "/tmp/SamaraExport/Samara\.app"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "BLOCKED: Manual copy of Samara.app to /Applications is forbidden. Use ~/.claude-mind/system/bin/update-samara which handles signing and notarization correctly."}}'
            exit 0
        fi
    fi
    if echo "$COMMAND" | grep -qE "xcodebuild.*Debug.*Samara" && echo "$COMMAND" | grep -q "build"; then
        if ! echo "$COMMAND" | grep -q "test"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "BLOCKED: Debug builds should not be deployed. Use ~/.claude-mind/system/bin/update-samara for proper Release + notarized builds."}}'
            exit 0
        fi
    fi

    # --- Check autonomous media capture ---
    MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
    IS_MEDIA=false
    CAPTURE_TYPE=""
    if echo "$COMMAND" | grep -qiE "imagesnap|ffmpeg.*video|avfoundation|/look"; then
        IS_MEDIA=true; CAPTURE_TYPE="webcam"
    fi
    if echo "$COMMAND" | grep -qiE "screencapture|screenshot"; then
        IS_MEDIA=true; CAPTURE_TYPE="screenshot"
    fi
    if [ "$IS_MEDIA" = true ]; then
        EXPLICIT_REQUEST_MARKER="$MIND_PATH/state/.media-request-explicit"
        if [ -f "$EXPLICIT_REQUEST_MARKER" ]; then
            MARKER_AGE=$(($(date +%s) - $(stat -f %m "$EXPLICIT_REQUEST_MARKER" 2>/dev/null || echo 0)))
            if [ "$MARKER_AGE" -lt 300 ]; then
                echo "$ALLOW"; exit 0
            fi
        fi
        EPISODE_FILE="$MIND_PATH/memory/episodes/$(date +%Y-%m-%d).md"
        [ -f "$EPISODE_FILE" ] && echo -e "\n- $(date '+%H:%M') [Hook] Blocked autonomous $CAPTURE_TYPE capture (ask first)" >> "$EPISODE_FILE"
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"Privacy-sensitive action ($CAPTURE_TYPE capture) requires explicit user request. Ask first before capturing photos or screenshots autonomously.\"}}"
        exit 0
    fi

    echo "$ALLOW"
    ;;

Skill)
    # --- Check autonomous media capture (Skill: look) ---
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // ""' 2>/dev/null)
    if [ "$SKILL_NAME" = "look" ]; then
        MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
        EXPLICIT_REQUEST_MARKER="$MIND_PATH/state/.media-request-explicit"
        if [ -f "$EXPLICIT_REQUEST_MARKER" ]; then
            MARKER_AGE=$(($(date +%s) - $(stat -f %m "$EXPLICIT_REQUEST_MARKER" 2>/dev/null || echo 0)))
            if [ "$MARKER_AGE" -lt 300 ]; then
                echo "$ALLOW"; exit 0
            fi
        fi
        EPISODE_FILE="$MIND_PATH/memory/episodes/$(date +%Y-%m-%d).md"
        [ -f "$EPISODE_FILE" ] && echo -e "\n- $(date '+%H:%M') [Hook] Blocked autonomous webcam capture (ask first)" >> "$EPISODE_FILE"
        echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Privacy-sensitive action (webcam capture) requires explicit user request. Ask first before capturing photos or screenshots autonomously."}}'
        exit 0
    fi

    # --- Local model guardrail for Skill ---
    if [ "$IS_LOCAL" = true ]; then
        # Block messaging/posting skills
        if echo "$SKILL_NAME" | grep -qE "bluesky|email|voice-call"; then
            echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Local model guardrail: Cannot use communication skills"}}'
            exit 0
        fi
    fi

    echo "$ALLOW"
    ;;

*)
    echo "$ALLOW"
    ;;
esac
