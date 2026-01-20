#!/bin/bash
#
# birth.sh - Bootstrap a new Claude organism from templates
#
# Usage: ./birth.sh [config.json] [target_directory]
#
# Arguments:
#   config.json      - Path to configuration file (default: ./config.example.json)
#   target_directory - Where to create ~/.claude-mind structure (default: ~/.claude-mind)
#
# This script:
#   1. Reads configuration from JSON
#   2. Fills template placeholders with config values
#   3. Creates the full directory structure
#   4. Copies scripts and sets up launchd services
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/config.example.json}"
TARGET_DIR="${2:-${SAMARA_MIND_PATH:-${MIND_PATH:-$HOME/.claude-mind}}}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Run: brew install jq"
        exit 1
    fi
}

# Validate config file
validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Check required fields
    local required_fields=(
        ".entity.name"
        ".collaborator.name"
        ".collaborator.phone"
        ".collaborator.email"
    )

    for field in "${required_fields[@]}"; do
        local value=$(jq -r "$field" "$CONFIG_FILE" 2>/dev/null)
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            log_error "Missing required config field: $field"
            exit 1
        fi
    done

    log_success "Config validated: $CONFIG_FILE"
}

# Load config values
load_config() {
    ENTITY_NAME=$(jq -r '.entity.name // "Claude"' "$CONFIG_FILE")
    ENTITY_ICLOUD=$(jq -r '.entity.icloud // ""' "$CONFIG_FILE")
    ENTITY_BLUESKY=$(jq -r '.entity.bluesky // ""' "$CONFIG_FILE")
    ENTITY_GITHUB=$(jq -r '.entity.github // ""' "$CONFIG_FILE")

    COLLABORATOR_NAME=$(jq -r '.collaborator.name' "$CONFIG_FILE")
    COLLABORATOR_PHONE=$(jq -r '.collaborator.phone' "$CONFIG_FILE")
    COLLABORATOR_EMAIL=$(jq -r '.collaborator.email' "$CONFIG_FILE")
    COLLABORATOR_BLUESKY=$(jq -r '.collaborator.bluesky // ""' "$CONFIG_FILE")

    NOTES_LOCATION=$(jq -r '.notes.location // "Claude Location Log"' "$CONFIG_FILE")
    NOTES_SCRATCHPAD=$(jq -r '.notes.scratchpad // "Claude Scratchpad"' "$CONFIG_FILE")

    MAIL_ACCOUNT=$(jq -r '.mail.account // "iCloud"' "$CONFIG_FILE")

    # Birth date for records
    BIRTH_DATE=$(date +"%Y-%m-%d")

    log_info "Entity: $ENTITY_NAME"
    log_info "Collaborator: $COLLABORATOR_NAME"
}

# Fill template placeholders
fill_template() {
    local template_file="$1"
    local output_file="$2"

    if [ ! -f "$template_file" ]; then
        log_error "Template not found: $template_file"
        return 1
    fi

    # Read template and replace placeholders
    cat "$template_file" | \
        sed "s/{{entity.name}}/$ENTITY_NAME/g" | \
        sed "s/{{entity.icloud}}/$ENTITY_ICLOUD/g" | \
        sed "s/{{entity.bluesky}}/$ENTITY_BLUESKY/g" | \
        sed "s/{{entity.github}}/$ENTITY_GITHUB/g" | \
        sed "s/{{collaborator.name}}/$COLLABORATOR_NAME/g" | \
        sed "s/{{collaborator.phone}}/$COLLABORATOR_PHONE/g" | \
        sed "s/{{collaborator.email}}/$COLLABORATOR_EMAIL/g" | \
        sed "s/{{collaborator.bluesky}}/$COLLABORATOR_BLUESKY/g" | \
        sed "s/{{notes.location}}/$NOTES_LOCATION/g" | \
        sed "s/{{notes.scratchpad}}/$NOTES_SCRATCHPAD/g" | \
        sed "s/{{mail.account}}/$MAIL_ACCOUNT/g" | \
        sed "s/{{birth_date}}/$BIRTH_DATE/g" \
        > "$output_file"

    log_success "Created: $output_file"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure at $TARGET_DIR"

    mkdir -p "$TARGET_DIR"/{memory/episodes,memory/reflections,memory/people,capabilities,scratch,outbox,bin,lib,logs,credentials,sessions,state,senses}

    log_success "Directory structure created"
}

# Fill and install templates
install_templates() {
    log_info "Installing templates..."

    # Core files
    fill_template "$SCRIPT_DIR/templates/identity.template.md" "$TARGET_DIR/identity.md"
    fill_template "$SCRIPT_DIR/templates/goals.template.md" "$TARGET_DIR/goals.md"
    fill_template "$SCRIPT_DIR/templates/inventory.template.md" "$TARGET_DIR/capabilities/inventory.md"

    # Create empty placeholder files
    local collaborator_lower=$(echo "$COLLABORATOR_NAME" | tr '[:upper:]' '[:lower:]')

    # Create people directory structure for collaborator
    mkdir -p "$TARGET_DIR/memory/people/${collaborator_lower}/artifacts"
    echo "# $COLLABORATOR_NAME" > "$TARGET_DIR/memory/people/${collaborator_lower}/profile.md"
    echo "" >> "$TARGET_DIR/memory/people/${collaborator_lower}/profile.md"
    echo "<!-- Notes accumulate organically below -->" >> "$TARGET_DIR/memory/people/${collaborator_lower}/profile.md"

    # Copy people README from templates
    if [ -f "$SCRIPT_DIR/templates/memory/people/README.md" ]; then
        cp "$SCRIPT_DIR/templates/memory/people/README.md" "$TARGET_DIR/memory/people/"
    fi

    # Create symlink for backwards compatibility
    ln -sf "people/${collaborator_lower}/profile.md" "$TARGET_DIR/memory/about-${collaborator_lower}.md"

    touch "$TARGET_DIR/memory/learnings.md"
    touch "$TARGET_DIR/memory/observations.md"
    touch "$TARGET_DIR/memory/questions.md"
    touch "$TARGET_DIR/memory/decisions.md"
    touch "$TARGET_DIR/scratch/current.md"
    touch "$TARGET_DIR/outbox/for-${collaborator_lower}.md"

    log_success "Templates installed"
}

# Copy config file
install_config() {
    log_info "Installing config..."

    cp "$CONFIG_FILE" "$TARGET_DIR/config.json"

    log_success "Config installed at $TARGET_DIR/config.json"
}

# Symlink scripts from samara-main (changes propagate automatically)
install_scripts() {
    log_info "Installing scripts (symlinked from repo)..."

    if [ -d "$SCRIPT_DIR/scripts" ]; then
        # Symlink each script individually
        for script in "$SCRIPT_DIR/scripts"/*; do
            if [ -f "$script" ]; then
                local script_name=$(basename "$script")
                local target="$TARGET_DIR/bin/$script_name"

                # Remove existing if present
                if [ -L "$target" ] || [ -f "$target" ]; then
                    rm -f "$target"
                fi

                ln -s "$script" "$target"
            fi
        done
        log_success "Scripts symlinked from samara-main/scripts/"
        log_info "Edits to repo scripts will propagate to runtime automatically"
    else
        log_warn "No scripts directory found at $SCRIPT_DIR/scripts/"
        log_warn "You'll need to copy scripts manually"
    fi

    # Install lib/config.sh (copy, not symlink - will be customized per instance)
    if [ -d "$SCRIPT_DIR/lib" ]; then
        cp -r "$SCRIPT_DIR/lib/"* "$TARGET_DIR/lib/"
        log_success "Lib files installed"
    fi
}

# Install Claude Code skills
install_skills() {
    log_info "Installing Claude Code skills..."

    local skills_src="$SCRIPT_DIR/.claude/skills"
    local skills_dst="$HOME/.claude/skills"

    if [ -d "$skills_src" ]; then
        mkdir -p "$skills_dst"

        # Symlink each skill directory
        for skill_dir in "$skills_src"/*/; do
            if [ -d "$skill_dir" ]; then
                local skill_name=$(basename "$skill_dir")
                local target="$skills_dst/$skill_name"

                # Remove existing if present
                if [ -L "$target" ] || [ -d "$target" ]; then
                    rm -rf "$target"
                fi

                ln -s "$skill_dir" "$target"
                log_success "Linked skill: $skill_name"
            fi
        done

        log_success "Skills installed (symlinked to $skills_dst)"
    else
        log_warn "No skills directory found at $skills_src"
    fi
}

# Install Claude Code agents
install_agents() {
    log_info "Installing Claude Code agents..."

    local agents_src="$SCRIPT_DIR/.claude/agents"
    local agents_dst="$HOME/.claude/agents"

    if [ -d "$agents_src" ]; then
        # Remove existing if present
        if [ -L "$agents_dst" ] || [ -d "$agents_dst" ]; then
            rm -rf "$agents_dst"
        fi

        ln -s "$agents_src" "$agents_dst"
        log_success "Agents symlinked: $agents_dst → $agents_src"
    else
        log_warn "No agents directory found at $agents_src"
    fi
}

# Create runtime .claude symlink and CLAUDE.md
# This allows Claude Code to find hooks/skills/agents when invoked from ~/.claude-mind/
install_runtime_claude_config() {
    log_info "Setting up runtime Claude Code configuration..."

    # Symlink .claude directory (for hooks, settings when invoked from runtime)
    local claude_src="$SCRIPT_DIR/.claude"
    local claude_dst="$TARGET_DIR/.claude"

    if [ -d "$claude_src" ]; then
        # Remove existing if present
        if [ -L "$claude_dst" ] || [ -d "$claude_dst" ]; then
            rm -rf "$claude_dst"
        fi

        ln -s "$claude_src" "$claude_dst"
        log_success "Runtime .claude symlinked: $claude_dst → $claude_src"
    fi

    # Symlink CLAUDE.md
    local claudemd_src="$SCRIPT_DIR/CLAUDE.md"
    local claudemd_dst="$TARGET_DIR/CLAUDE.md"

    if [ -f "$claudemd_src" ]; then
        # Remove existing if present
        if [ -L "$claudemd_dst" ] || [ -f "$claudemd_dst" ]; then
            rm -f "$claudemd_dst"
        fi

        ln -s "$claudemd_src" "$claudemd_dst"
        log_success "Runtime CLAUDE.md symlinked: $claudemd_dst → $claudemd_src"
    fi
}

# Configure Claude Code global settings
configure_claude_code() {
    log_info "Configuring Claude Code retention policy..."

    local settings_file="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"

    # Create or update settings with 100-year retention
    if [ -f "$settings_file" ]; then
        # Merge cleanupPeriodDays into existing settings
        local temp_file=$(mktemp)
        jq '. + {cleanupPeriodDays: 36500}' "$settings_file" > "$temp_file"
        mv "$temp_file" "$settings_file"
        log_success "Updated existing Claude Code settings with 100-year retention"
    else
        # Create new settings file with retention policy
        cat > "$settings_file" << 'EOF'
{
  "cleanupPeriodDays": 36500
}
EOF
        log_success "Created Claude Code settings with 100-year retention"
    fi

    log_info "Session transcripts will be preserved for ~100 years at ~/.claude/projects/"
}

# Create launchd plist templates
create_launchd_templates() {
    log_info "Creating launchd templates..."

    local plist_dir="$TARGET_DIR/launchd"
    mkdir -p "$plist_dir"

    # Wake Adaptive (every 15 minutes - handles all wake scheduling)
    cat > "$plist_dir/com.claude.wake-adaptive.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.wake-adaptive</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/bin/wake-adaptive</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/wake-adaptive.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/wake-adaptive.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin</string>
    </dict>
</dict>
</plist>
EOF

    # Dream
    cat > "$plist_dir/com.claude.dream.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.dream</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/bin/dream</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/dream.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/dream.log</string>
</dict>
</plist>
EOF

    # Bluesky Watcher (every 15 minutes)
    cat > "$plist_dir/com.claude.bluesky-watcher.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.bluesky-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$SCRIPT_DIR/services/bluesky-watcher/server.py</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/bluesky-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/bluesky-watcher.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
EOF

    # GitHub Watcher (every 15 minutes)
    cat > "$plist_dir/com.claude.github-watcher.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.github-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$SCRIPT_DIR/services/github-watcher/server.py</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/github-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/github-watcher.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
EOF

    # X/Twitter Watcher (every 15 minutes)
    cat > "$plist_dir/com.claude.x-watcher.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.x-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$SCRIPT_DIR/services/x-watcher/server.py</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/x-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/x-watcher.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
EOF

    log_success "launchd templates created in $plist_dir/"
    log_info "To install: cp $plist_dir/*.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.claude.*.plist"
}

# Print next steps
print_next_steps() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    Birth Complete!                            ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps to complete the organism setup:"
    echo ""
    echo "1. Build and install Samara.app:"
    echo "   cd ~/Developer/Samara"
    echo "   # Update main.swift to use config if needed"
    echo "   xcodebuild archive ..."
    echo ""
    echo "2. Grant Full Disk Access to Samara.app:"
    echo "   System Settings > Privacy & Security > Full Disk Access"
    echo ""
    echo "3. Install launchd services:"
    echo "   cp $TARGET_DIR/launchd/*.plist ~/Library/LaunchAgents/"
    echo "   launchctl load ~/Library/LaunchAgents/com.claude.wake-adaptive.plist"
    echo "   launchctl load ~/Library/LaunchAgents/com.claude.dream.plist"
    echo ""
    echo "4. Set up credentials:"
    echo "   - Bluesky app password: $TARGET_DIR/credentials/bluesky.json"
    echo "   - GitHub token: $TARGET_DIR/credentials/github.txt"
    echo ""
    echo "5. Launch Samara:"
    echo "   open /Applications/Samara.app"
    echo ""
    echo "6. Send a test message from $COLLABORATOR_NAME's phone!"
    echo ""
    echo "Note: Claude Code session retention has been configured for ~100 years."
    echo "      All conversations will be preserved at ~/.claude/projects/"
    echo ""
}

# Main
main() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}              Claude Organism Birth Script                     ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    check_dependencies
    validate_config
    load_config

    # Confirm before proceeding
    echo ""
    echo "This will create a new organism at: $TARGET_DIR"
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi

    create_directories
    install_config
    install_templates
    install_scripts
    install_skills
    install_agents
    install_runtime_claude_config
    configure_claude_code
    create_launchd_templates
    print_next_steps
}

main "$@"
