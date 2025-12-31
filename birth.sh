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
TARGET_DIR="${2:-$HOME/.claude-mind}"

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

    mkdir -p "$TARGET_DIR"/{memory/episodes,memory/reflections,capabilities,scratch,outbox,bin,lib,logs,credentials,sessions}

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
    touch "$TARGET_DIR/memory/about-${collaborator_lower}.md"
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

# Copy scripts from samara-main
install_scripts() {
    log_info "Installing scripts..."

    if [ -d "$SCRIPT_DIR/scripts" ]; then
        cp -r "$SCRIPT_DIR/scripts/"* "$TARGET_DIR/bin/"
        chmod +x "$TARGET_DIR/bin/"*
        log_success "Scripts installed from samara-main/scripts/"
    else
        log_warn "No scripts directory found at $SCRIPT_DIR/scripts/"
        log_warn "You'll need to copy scripts manually"
    fi

    # Install lib/config.sh
    if [ -d "$SCRIPT_DIR/lib" ]; then
        cp -r "$SCRIPT_DIR/lib/"* "$TARGET_DIR/lib/"
        log_success "Lib files installed"
    fi
}

# Create launchd plist templates
create_launchd_templates() {
    log_info "Creating launchd templates..."

    local plist_dir="$TARGET_DIR/launchd"
    mkdir -p "$plist_dir"

    # Wake morning
    cat > "$plist_dir/com.claude.wake-morning.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.wake-morning</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/bin/wake</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
</dict>
</plist>
EOF

    # Wake afternoon
    cat > "$plist_dir/com.claude.wake-afternoon.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.wake-afternoon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/bin/wake</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>14</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
</dict>
</plist>
EOF

    # Wake evening
    cat > "$plist_dir/com.claude.wake-evening.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.wake-evening</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/bin/wake</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>20</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
    <key>StandardErrorPath</key>
    <string>$TARGET_DIR/logs/wake.log</string>
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
    echo "   launchctl load ~/Library/LaunchAgents/com.claude.wake-morning.plist"
    echo "   launchctl load ~/Library/LaunchAgents/com.claude.wake-afternoon.plist"
    echo "   launchctl load ~/Library/LaunchAgents/com.claude.wake-evening.plist"
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
    create_launchd_templates
    print_next_steps
}

main "$@"
