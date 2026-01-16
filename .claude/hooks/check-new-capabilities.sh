#!/bin/bash
# Stop hook: Check for new capabilities and auto-integrate them
#
# Scans git status for new files in capability-related directories.
# - Auto-generates skills manifest if skills changed
# - Adds stub entries to inventory.md for new capabilities
# - Logs changes to capabilities changelog
#
# Input: JSON with session info on stdin (ignored)
# Output: JSON with {ok: boolean, message?: string}

# Note: NOT using set -e to ensure we always output valid JSON

MIND_PATH="${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}"
REPO_DIR="$HOME/Developer/samara-main"
INVENTORY="$MIND_PATH/capabilities/inventory.md"
CHANGELOG="$MIND_PATH/capabilities/changelog.md"
MANIFEST="$REPO_DIR/.claude/skills-manifest.json"
TODAY=$(date +%Y-%m-%d)

# Capability-related directories to check
CAPABILITY_DIRS="scripts .claude/skills services"

# Get new (untracked) files in capability directories
cd "$REPO_DIR" 2>/dev/null || {
    echo '{"ok": true}'
    exit 0
}

NEW_FILES=""
NEW_SKILLS=""
for dir in $CAPABILITY_DIRS; do
    if [ -d "$dir" ]; then
        # Untracked files
        untracked=$(git ls-files --others --exclude-standard "$dir" 2>/dev/null)
        if [ -n "$untracked" ]; then
            NEW_FILES="$NEW_FILES$untracked"$'\n'
            # Track skills separately
            if [ "$dir" = ".claude/skills" ]; then
                NEW_SKILLS="$NEW_SKILLS$untracked"$'\n'
            fi
        fi
    fi
done

# Remove empty lines
NEW_FILES=$(echo "$NEW_FILES" | grep -v '^$')
NEW_SKILLS=$(echo "$NEW_SKILLS" | grep -v '^$')

ACTIONS=""

# 1. Regenerate skills manifest if skills changed
if [ -n "$NEW_SKILLS" ]; then
    # Generate fresh manifest
    SKILLS_DIR="$REPO_DIR/.claude/skills"
    if [ -d "$SKILLS_DIR" ]; then
        echo '{"skills": [' > "$MANIFEST.tmp"
        FIRST=true
        for skill_dir in "$SKILLS_DIR"/*/; do
            [ -d "$skill_dir" ] || continue
            SKILL_NAME=$(basename "$skill_dir")
            SKILL_FILE="$skill_dir/SKILL.md"
            [ -f "$SKILL_FILE" ] || SKILL_FILE="$skill_dir/SKILL.yaml"
            [ -f "$SKILL_FILE" ] || continue

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo "," >> "$MANIFEST.tmp"
            fi

            # Extract description from frontmatter
            DESC=$(grep -A1 "^description:" "$SKILL_FILE" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' | head -c 100)
            [ -z "$DESC" ] && DESC="No description"

            echo -n "  {\"name\": \"$SKILL_NAME\", \"description\": \"$DESC\"}" >> "$MANIFEST.tmp"
        done
        echo '' >> "$MANIFEST.tmp"
        echo ']}' >> "$MANIFEST.tmp"
        mv "$MANIFEST.tmp" "$MANIFEST"
        ACTIONS+="Regenerated skills manifest. "
    fi
fi

# 2. Check for undocumented capabilities and add stubs
if [ -z "$NEW_FILES" ]; then
    if [ -n "$ACTIONS" ]; then
        echo "{\"ok\": true, \"message\": \"$ACTIONS\"}"
    else
        echo '{"ok": true}'
    fi
    exit 0
fi

UNDOCUMENTED=""
STUBS_ADDED=""

while IFS= read -r file; do
    [ -z "$file" ] && continue
    basename=$(basename "$file")

    if ! grep -q "$basename" "$INVENTORY" 2>/dev/null; then
        UNDOCUMENTED="$UNDOCUMENTED- $file"$'\n'

        # Determine type and add stub to inventory
        case "$file" in
            scripts/*)
                STUB="| \`$basename\` | TODO: Add description |"
                # Find the Scripts section and add after the table header
                if grep -q "^## Scripts" "$INVENTORY"; then
                    # Add to end of scripts table (before next section)
                    sed -i '' "/^## Scripts/,/^## /{/^|.*|$/a\\
$STUB
}" "$INVENTORY" 2>/dev/null || true
                fi
                STUBS_ADDED+="$basename "
                ;;
            .claude/skills/*)
                STUB="| \`/$basename\` | TODO: Add description |"
                if grep -q "^## Skills" "$INVENTORY"; then
                    sed -i '' "/^## Skills/,/^## /{/^|.*|$/a\\
$STUB
}" "$INVENTORY" 2>/dev/null || true
                fi
                STUBS_ADDED+="$basename "
                ;;
            services/*)
                STUB="| \`$basename\` | TODO | TODO: Add description |"
                if grep -q "^## Services" "$INVENTORY"; then
                    sed -i '' "/^## Services/,/^## /{/^|.*|$/a\\
$STUB
}" "$INVENTORY" 2>/dev/null || true
                fi
                STUBS_ADDED+="$basename "
                ;;
        esac
    fi
done <<< "$NEW_FILES"

# 3. Log to changelog
if [ -n "$STUBS_ADDED" ]; then
    echo "" >> "$CHANGELOG"
    echo "- $TODAY: Auto-detected new capabilities: $STUBS_ADDED" >> "$CHANGELOG"
    ACTIONS+="Added stubs for: $STUBS_ADDED. "
fi

UNDOCUMENTED=$(echo "$UNDOCUMENTED" | grep -v '^$')

if [ -n "$UNDOCUMENTED" ]; then
    # Escape for JSON
    UNDOCUMENTED_ESCAPED=$(echo "$UNDOCUMENTED" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')
    ACTIONS+="New capabilities need documentation: $UNDOCUMENTED_ESCAPED"
fi

if [ -n "$ACTIONS" ]; then
    echo "{\"ok\": true, \"message\": \"$ACTIONS\"}"
else
    echo '{"ok": true}'
fi
