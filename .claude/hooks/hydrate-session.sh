#!/bin/bash
# SessionStart hook: Hydrate session with context
#
# Loads relevant context at session start:
# - Most recent ledger handoff (if exists)
# - Pending sense events count
# - Today's episode summary
# - System health status
#
# Input: JSON with source (startup|resume|clear|compact) on stdin
# Output: JSON with hookSpecificOutput.additionalContext

# Note: NOT using set -e because some checks may fail expectedly

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
INPUT=$(cat)

SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Build context sections
CONTEXT=""

# 1. Check for recent handoff
HANDOFF_DIR="$MIND_PATH/state/ledgers"
if [ -d "$HANDOFF_DIR" ]; then
    LATEST_HANDOFF=$(ls -t "$HANDOFF_DIR"/*.md 2>/dev/null | head -1)
    if [ -n "$LATEST_HANDOFF" ] && [ -f "$LATEST_HANDOFF" ]; then
        HANDOFF_AGE_HOURS=$(( ($(date +%s) - $(stat -f %m "$LATEST_HANDOFF")) / 3600 ))
        if [ "$HANDOFF_AGE_HOURS" -lt 24 ]; then
            HANDOFF_CONTENT=$(head -50 "$LATEST_HANDOFF")
            CONTEXT+="## Recent Handoff (${HANDOFF_AGE_HOURS}h ago)\n\n$HANDOFF_CONTENT\n\n"
        fi
    fi
fi

# 2. Check pending sense events
SENSES_DIR="$MIND_PATH/senses"
if [ -d "$SENSES_DIR" ]; then
    # Count non-failed, non-processed events
    PENDING_COUNT=$(find "$SENSES_DIR" -name "*.json" -not -name "*.failed.json" -not -name "*.processed.json" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PENDING_COUNT" -gt 0 ]; then
        CONTEXT+="## Pending Sense Events: $PENDING_COUNT\n\n"
        # Show first 3 event summaries
        for EVENT_FILE in $(find "$SENSES_DIR" -name "*.json" -not -name "*.failed.json" -not -name "*.processed.json" 2>/dev/null | head -3); do
            EVENT_TYPE=$(jq -r '.type // "unknown"' "$EVENT_FILE" 2>/dev/null)
            EVENT_TIME=$(jq -r '.timestamp // ""' "$EVENT_FILE" 2>/dev/null | cut -d'T' -f2 | cut -d'.' -f1)
            CONTEXT+="- $EVENT_TYPE at $EVENT_TIME\n"
        done
        CONTEXT+="\n"
    fi
fi

# 3. Today's episode summary (last 20 lines)
TODAY=$(date +%Y-%m-%d)
EPISODE_FILE="$MIND_PATH/memory/episodes/$TODAY.md"
if [ -f "$EPISODE_FILE" ]; then
    EPISODE_SIZE=$(wc -l < "$EPISODE_FILE" | tr -d ' ')
    if [ "$EPISODE_SIZE" -gt 5 ]; then
        CONTEXT+="## Today's Episode ($EPISODE_SIZE lines)\n\n"
        # Get section headers to show what happened today
        SECTIONS=$(grep "^## " "$EPISODE_FILE" | tail -5 | sed 's/^/- /')
        CONTEXT+="Recent sections:\n$SECTIONS\n\n"
    fi
fi

# 4. System health check
HEALTH_ISSUES=""

# Check if Samara is running
if ! pgrep -q "Samara"; then
    HEALTH_ISSUES+="- Samara.app not running\n"
fi

# Check critical launchd services
for SERVICE in "wake-adaptive" "dream"; do
    if ! launchctl list 2>/dev/null | grep -q "com.claude.$SERVICE"; then
        HEALTH_ISSUES+="- $SERVICE service not loaded\n"
    fi
done

# Check drift status (quick check via state file if recent)
DRIFT_FILE="$MIND_PATH/state/drift-report.json"
if [ -f "$DRIFT_FILE" ]; then
    DRIFT_AGE_HOURS=$(( ($(date +%s) - $(stat -f %m "$DRIFT_FILE")) / 3600 ))
    if [ "$DRIFT_AGE_HOURS" -lt 12 ]; then
        DRIFT_COUNT=$(jq -r '.drift_count // 0' "$DRIFT_FILE" 2>/dev/null)
        if [ "$DRIFT_COUNT" -gt 0 ]; then
            HEALTH_ISSUES+="- System drift detected ($DRIFT_COUNT items)\n"
        fi
    fi
fi

if [ -n "$HEALTH_ISSUES" ]; then
    CONTEXT+="## Health Alerts\n\n$HEALTH_ISSUES\n"
fi

# 5. Capability staleness reminders
# Based on repeated "remember you have access to..." friction
CAPABILITY_REMINDERS=""

# Check last X post time
X_STATE="$MIND_PATH/state/x-engage-state.json"
if [ -f "$X_STATE" ]; then
    LAST_POST=$(jq -r '.last_proactive_post // .last_post_time // ""' "$X_STATE" 2>/dev/null)
    if [ -n "$LAST_POST" ] && [ "$LAST_POST" != "null" ]; then
        # Handle ISO format (2026-01-15T03:06:19Z) or Unix timestamp
        if echo "$LAST_POST" | grep -qE '^[0-9]{4}-'; then
            # ISO format - convert to epoch
            LAST_POST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_POST%%.*}" +%s 2>/dev/null || echo 0)
        else
            LAST_POST_EPOCH="$LAST_POST"
        fi
        if [ "$LAST_POST_EPOCH" != "0" ]; then
            HOURS_SINCE=$(( ($(date +%s) - $LAST_POST_EPOCH) / 3600 ))
            if [ "$HOURS_SINCE" -gt 24 ]; then
                CAPABILITY_REMINDERS+="- X/Twitter: Last post ${HOURS_SINCE}h ago\n"
            fi
        fi
    fi
fi

# Check X mentions
X_WATCHER_STATE="$MIND_PATH/state/x-watcher-state.json"
if [ -f "$X_WATCHER_STATE" ]; then
    PENDING_MENTIONS=$(jq -r '.pending_mentions // 0' "$X_WATCHER_STATE" 2>/dev/null)
    if [ "$PENDING_MENTIONS" != "0" ] && [ "$PENDING_MENTIONS" != "null" ] && [ "$PENDING_MENTIONS" -gt 0 ]; then
        CAPABILITY_REMINDERS+="- X/Twitter: $PENDING_MENTIONS pending mentions\n"
    fi
fi

# Check wallet last check time (use file modification time)
WALLET_STATE="$MIND_PATH/state/wallet-state.json"
if [ -f "$WALLET_STATE" ]; then
    WALLET_MTIME=$(stat -f %m "$WALLET_STATE" 2>/dev/null || echo 0)
    if [ "$WALLET_MTIME" != "0" ]; then
        HOURS_SINCE=$(( ($(date +%s) - $WALLET_MTIME) / 3600 ))
        if [ "$HOURS_SINCE" -gt 48 ]; then
            CAPABILITY_REMINDERS+="- Wallet: Last check ${HOURS_SINCE}h ago\n"
        fi
    fi
fi

# Check for unread shared links in senses
UNREAD_LINKS=$(find "$MIND_PATH/senses" -name "*.json" -not -name "*.processed.json" -exec grep -l '"type".*:.*"shared_link"' {} \; 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNREAD_LINKS" -gt 0 ]; then
    CAPABILITY_REMINDERS+="- Shared links: $UNREAD_LINKS unread\n"
fi

# Check if reference directories have recent additions (for creative prompts)
MIRROR_DIR="$MIND_PATH/credentials/mirror"
if [ -d "$MIRROR_DIR" ]; then
    RECENT_MIRROR=$(find "$MIRROR_DIR" -type f -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    if [ "$RECENT_MIRROR" -gt 0 ]; then
        CAPABILITY_REMINDERS+="- Mirror dir: $RECENT_MIRROR recent reference images\n"
    fi
fi

if [ -n "$CAPABILITY_REMINDERS" ]; then
    CONTEXT+="## Capability Reminders\n\n$CAPABILITY_REMINDERS\n"
fi

# 6. Session source context
case "$SOURCE" in
    resume)
        CONTEXT+="*Session resumed - previous context preserved*\n"
        ;;
    compact)
        CONTEXT+="*Session compacted - some earlier context was summarized*\n"
        ;;
    clear)
        CONTEXT+="*Session cleared - fresh start*\n"
        ;;
esac

# Output JSON with additionalContext
if [ -n "$CONTEXT" ]; then
    # Escape for JSON
    CONTEXT_ESCAPED=$(echo -e "$CONTEXT" | jq -Rs .)
    echo "{\"hookSpecificOutput\": {\"additionalContext\": $CONTEXT_ESCAPED}}"
else
    echo '{"ok": true}'
fi
