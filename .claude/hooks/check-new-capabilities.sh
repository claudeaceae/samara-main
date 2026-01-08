#!/bin/bash
# Stop hook: Check for new capabilities that should be documented
#
# Scans git status for new files in capability-related directories.
# Reminds to document in inventory.md if undocumented capabilities exist.
#
# Input: JSON with session info on stdin (ignored)
# Output: JSON with {ok: boolean, message?: string}

# Capability-related directories to check
CAPABILITY_DIRS="scripts .claude/skills services"
REPO_DIR="$HOME/Developer/samara-main"
INVENTORY="$HOME/.claude-mind/capabilities/inventory.md"

# Get new (untracked) files in capability directories
cd "$REPO_DIR" 2>/dev/null || {
    echo '{"ok": true}'
    exit 0
}

NEW_FILES=""
for dir in $CAPABILITY_DIRS; do
    if [ -d "$dir" ]; then
        # Untracked files
        untracked=$(git ls-files --others --exclude-standard "$dir" 2>/dev/null)
        if [ -n "$untracked" ]; then
            NEW_FILES="$NEW_FILES$untracked"$'\n'
        fi
    fi
done

# Remove empty lines
NEW_FILES=$(echo "$NEW_FILES" | grep -v '^$')

if [ -z "$NEW_FILES" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Check which new files are already documented in inventory.md
UNDOCUMENTED=""
while IFS= read -r file; do
    basename=$(basename "$file")
    if ! grep -q "$basename" "$INVENTORY" 2>/dev/null; then
        UNDOCUMENTED="$UNDOCUMENTED- $file"$'\n'
    fi
done <<< "$NEW_FILES"

UNDOCUMENTED=$(echo "$UNDOCUMENTED" | grep -v '^$')

if [ -z "$UNDOCUMENTED" ]; then
    echo '{"ok": true}'
    exit 0
fi

# Escape for JSON
UNDOCUMENTED_ESCAPED=$(echo "$UNDOCUMENTED" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')

echo "{\"ok\": true, \"message\": \"New capabilities detected. Consider documenting in inventory.md: $UNDOCUMENTED_ESCAPED\"}"
