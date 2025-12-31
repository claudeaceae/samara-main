#!/bin/bash
# Configuration helper for Claude Mind scripts
# Source this file to get config values with fallbacks
#
# Usage:
#   source "$HOME/.claude-mind/lib/config.sh"
#   echo "Collaborator phone: $COLLABORATOR_PHONE"

CONFIG_FILE="$HOME/.claude-mind/config.json"

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
    local path="$1"
    local fallback="$2"

    if [ "$CONFIG_AVAILABLE" = true ]; then
        local value
        value=$(jq -r "$path // empty" "$CONFIG_FILE" 2>/dev/null)
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
ENTITY_GITHUB=$(config_get '.entity.github' '')

# Collaborator (human) configuration
COLLABORATOR_NAME=$(config_get '.collaborator.name' '')
COLLABORATOR_PHONE=$(config_get '.collaborator.phone' '')
COLLABORATOR_EMAIL=$(config_get '.collaborator.email' '')
COLLABORATOR_BLUESKY=$(config_get '.collaborator.bluesky' '')

# Notes configuration
NOTE_LOCATION=$(config_get '.notes.location' 'Claude Location Log')
NOTE_SCRATCHPAD=$(config_get '.notes.scratchpad' 'Claude Scratchpad')

# Mail configuration
MAIL_ACCOUNT=$(config_get '.mail.account' 'iCloud')

# Export all variables
export ENTITY_NAME ENTITY_ICLOUD ENTITY_BLUESKY ENTITY_GITHUB
export COLLABORATOR_NAME COLLABORATOR_PHONE COLLABORATOR_EMAIL COLLABORATOR_BLUESKY
export NOTE_LOCATION NOTE_SCRATCHPAD
export MAIL_ACCOUNT
export CONFIG_FILE CONFIG_AVAILABLE
