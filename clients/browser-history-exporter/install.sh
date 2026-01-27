#!/bin/bash
#
# Browser History Exporter - Installer
#
# Installs the browser history exporter on the client machine (your Mac).
# This script copies the exporter to a shared location, creates a Python
# virtual environment with dependencies, and sets up a launchd agent to
# run it every 15 minutes.
#
# Usage:
#   ./install.sh [--secret <webhook_secret>]
#
# After installation:
#   1. Run a manual test: $INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/exporter.py
#   2. The launchd agent will start automatically every 15 minutes

set -eo pipefail

# Paths
INSTALL_DIR="/Users/Shared/.claude-client/browser-history-exporter"
VENV_DIR="$INSTALL_DIR/venv"
CONFIG_DIR="$HOME/.claude-client"
LOG_DIR="/Users/Shared/.claude-client/logs"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.claude.browser-history-exporter.plist"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
WEBHOOK_SECRET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --secret) WEBHOOK_SECRET="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "Browser History Exporter - Installer"
echo "====================================="
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"

# Copy exporter script
echo "Installing exporter..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/exporter.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/exporter.py"

# Create virtual environment and install dependencies
echo "Setting up Python virtual environment..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install requests -q
echo "  Installed: $("$VENV_DIR/bin/python3" -c 'import requests; print(f"requests {requests.__version__}")')"

# Create default config if it doesn't exist
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    echo "Creating configuration..."
    SECRET="${WEBHOOK_SECRET:-your-shared-secret-here}"
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "webhook_url": "https://webhooks.organelle.co/webhook/browser_history",
  "webhook_secret": "$SECRET",
  "browsers": ["dia", "safari"],
  "poll_interval_min": 15,
  "device_name": "$(scutil --get ComputerName 2>/dev/null || hostname -s)"
}
EOF
    if [[ -z "$WEBHOOK_SECRET" ]]; then
        echo -e "${YELLOW}IMPORTANT: Edit $CONFIG_DIR/config.json and set webhook_secret${NC}"
    else
        echo "  Config written with provided secret."
    fi
else
    echo "  Config already exists at $CONFIG_DIR/config.json (not overwriting)"
fi

# Install launchd agent
echo "Installing launchd agent..."
cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.browser-history-exporter</string>

    <key>ProgramArguments</key>
    <array>
        <string>$VENV_DIR/bin/python3</string>
        <string>$INSTALL_DIR/exporter.py</string>
    </array>

    <key>StartInterval</key>
    <integer>900</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/browser-history-exporter.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/browser-history-exporter.err</string>
</dict>
</plist>
EOF

# Unload existing agent if present
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true

# Load the agent
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "  Config:  $CONFIG_DIR/config.json"
echo "  Logs:    $LOG_DIR/browser-history-exporter.{log,err}"
echo "  Venv:    $VENV_DIR/"
echo ""
echo "Test manually:"
echo "  $VENV_DIR/bin/python3 $INSTALL_DIR/exporter.py"
echo ""
echo "To uninstall:"
echo "  launchctl unload $LAUNCH_AGENTS_DIR/$PLIST_NAME"
echo "  rm -rf /Users/Shared/.claude-client $LAUNCH_AGENTS_DIR/$PLIST_NAME $CONFIG_DIR"
