#!/bin/bash
#
# Browser History Exporter - Installer
#
# Installs the browser history exporter on the client machine (your Mac).
# This script copies the exporter to a shared location and sets up a launchd
# agent to run it every 15 minutes.
#
# Usage:
#   ./install.sh
#
# After installation:
#   1. Edit ~/.claude-client/config.json with your webhook URL and secret
#   2. Run 'python3 ~/.claude-client/browser-history-exporter/exporter.py' to test
#   3. The launchd agent will start automatically

set -eo pipefail

# Paths
INSTALL_DIR="/Users/Shared/.claude-client/browser-history-exporter"
CONFIG_DIR="$HOME/.claude-client"
LOG_DIR="/Users/Shared/.claude-client/logs"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.claude.browser-history-exporter.plist"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Install Python dependencies
echo "Installing Python dependencies..."
if ! python3 -c "import requests" 2>/dev/null; then
    pip3 install --user requests
fi

# Create default config if it doesn't exist
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    echo "Creating default configuration..."
    cat > "$CONFIG_DIR/config.json" << 'EOF'
{
  "webhook_url": "https://your-cloudflare-tunnel-url/webhook/browser_history",
  "webhook_secret": "your-shared-secret-here",
  "browsers": ["dia", "safari"],
  "poll_interval_min": 15,
  "device_name": "eriks-macbook"
}
EOF
    echo -e "${YELLOW}IMPORTANT: Edit $CONFIG_DIR/config.json with your webhook URL and secret${NC}"
fi

# Update plist with correct username
echo "Installing launchd agent..."
CURRENT_USER=$(whoami)
sed "s|/Users/Shared|/Users/Shared|g" "$SCRIPT_DIR/$PLIST_NAME" > "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# Unload existing agent if present
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true

# Load the agent
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit $CONFIG_DIR/config.json"
echo "     - Set webhook_url to your Claude webhook endpoint"
echo "     - Set webhook_secret to match the server's secret"
echo "     - Adjust browsers list if needed (default: dia, safari)"
echo ""
echo "  2. Test the exporter manually:"
echo "     python3 $INSTALL_DIR/exporter.py"
echo ""
echo "  3. The exporter will run automatically every 15 minutes"
echo ""
echo "Logs are at:"
echo "  $LOG_DIR/browser-history-exporter.log"
echo "  $LOG_DIR/browser-history-exporter.err"
echo ""
echo "To uninstall:"
echo "  launchctl unload $LAUNCH_AGENTS_DIR/$PLIST_NAME"
echo "  rm -rf $INSTALL_DIR $LAUNCH_AGENTS_DIR/$PLIST_NAME"
