#!/bin/bash
# Configuration helper for Claude Mind scripts
# Source this file to get config values with fallbacks
#
# Usage:
#   source "$HOME/.claude-mind/system/lib/config.sh"
#   echo "Collaborator phone: $COLLABORATOR_PHONE"

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
CONFIG_FILE="${CONFIG_FILE:-$MIND_PATH/config.json}"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Warning: jq not found, using fallback values" >&2
    CONFIG_AVAILABLE=false
else
    CONFIG_AVAILABLE=true
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Warning: config.json not found, using fallback values" >&2
    CONFIG_AVAILABLE=false
fi

# Helper function to read config with fallback
config_get() {
    local jq_filter="$1"
    local fallback="$2"

    if [ "$CONFIG_AVAILABLE" = true ]; then
        local value
        value=$(jq -r "$jq_filter // empty" "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
            return
        fi
    fi
    echo "$fallback"
}

# Entity (Claude) configuration
ENTITY_NAME=$(config_get '.entity.name' 'Claude')
ENTITY_ICLOUD=$(config_get '.entity.icloud' '')
ENTITY_BLUESKY=$(config_get '.entity.bluesky' '')
ENTITY_X=$(config_get '.entity.x' '')
ENTITY_GITHUB=$(config_get '.entity.github' '')

# Collaborator (human) configuration
COLLABORATOR_NAME=$(config_get '.collaborator.name' '')
COLLABORATOR_PHONE=$(config_get '.collaborator.phone' '')
COLLABORATOR_EMAIL=$(config_get '.collaborator.email' '')
COLLABORATOR_BLUESKY=$(config_get '.collaborator.bluesky' '')
COLLABORATOR_X=$(config_get '.collaborator.x' '')

# Derived values for convenience
COLLABORATOR_NAME_LOWER=$(echo "$COLLABORATOR_NAME" | tr '[:upper:]' '[:lower:]')

# Notes configuration (legacy)
NOTE_LOCATION=$(config_get '.notes.location' 'Claude Location Log')
NOTE_SCRATCHPAD=$(config_get '.notes.scratchpad' 'Claude Scratchpad')

# Shared workspace configuration (file-based notes)
SHARED_WORKSPACE_DIR=$(config_get '.sharedWorkspace.path' "$MIND_PATH/shared")
SHARED_WORKSPACE_SYNC=$(config_get '.sharedWorkspace.sync' 'false')
SHARED_SCRATCHPAD=$(config_get '.sharedWorkspace.scratchpad' 'scratchpad.md')
if [[ "$SHARED_SCRATCHPAD" = /* ]]; then
    SCRATCHPAD_FILE="$SHARED_SCRATCHPAD"
else
    SCRATCHPAD_FILE="$SHARED_WORKSPACE_DIR/$SHARED_SCRATCHPAD"
fi

# Mail configuration
MAIL_ACCOUNT=$(config_get '.mail.account' 'iCloud')

# Export all variables
export ENTITY_NAME ENTITY_ICLOUD ENTITY_BLUESKY ENTITY_X ENTITY_GITHUB
export COLLABORATOR_NAME COLLABORATOR_PHONE COLLABORATOR_EMAIL COLLABORATOR_BLUESKY COLLABORATOR_X COLLABORATOR_NAME_LOWER
export NOTE_LOCATION NOTE_SCRATCHPAD
export SHARED_WORKSPACE_DIR SHARED_WORKSPACE_SYNC SCRATCHPAD_FILE
export MAIL_ACCOUNT
export MIND_PATH CONFIG_FILE CONFIG_AVAILABLE
