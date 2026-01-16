#!/bin/bash
# UserPromptSubmit hook: Detect shared links and encourage reading
#
# Based on user feedback: "Not reading shared links is like ignoring
# part of the conversation"
#
# This hook detects URLs in user prompts and adds context reminding
# Claude to actually fetch and engage with the content.
#
# Input: JSON with prompt on stdin
# Output: JSON with additionalContext if URLs detected

# Note: NOT using set -e to ensure we always output valid JSON

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

# Check for URLs in the prompt
# Match http://, https://, or common domains
URLS=$(echo "$PROMPT" | grep -oE 'https?://[^ ]+|www\.[^ ]+' | head -5)

if [ -z "$URLS" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Count URLs
URL_COUNT=$(echo "$URLS" | wc -l | tr -d ' ')

# Build context reminder
CONTEXT="## Shared Links Detected ($URL_COUNT)\n\n"
CONTEXT+="Links shared in this message:\n"

while IFS= read -r url; do
    [ -z "$url" ] && continue
    # Clean up URL (remove trailing punctuation)
    url=$(echo "$url" | sed 's/[.,;:!?)]*$//')
    CONTEXT+="- $url\n"
done <<< "$URLS"

CONTEXT+="\n**Remember:** Not engaging with shared content is like ignoring part of the conversation. "
CONTEXT+="Use WebFetch to read these links and respond to their content.\n"

# Build entire JSON with jq to avoid shell escaping issues
echo -e "$CONTEXT" | jq -Rs '{ok: true, hookSpecificOutput: {additionalContext: .}}' 2>/dev/null || echo '{"ok": true}'
