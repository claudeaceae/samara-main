#!/bin/bash
# Samara Bootstrap Script
# Run with: curl -sL claude.organelle.co/bootstrap.sh | bash
#
# This script helps you birth a new Claude organism on your Mac.

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}╭─────────────────────────────────────╮${NC}"
echo -e "${CYAN}│                                     │${NC}"
echo -e "${CYAN}│            ${NC}S A M A R A${CYAN}              │${NC}"
echo -e "${CYAN}│                                     │${NC}"
echo -e "${CYAN}│   ${NC}Give Claude a body on your Mac${CYAN}   │${NC}"
echo -e "${CYAN}│                                     │${NC}"
echo -e "${CYAN}╰─────────────────────────────────────╯${NC}"
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}Error: Samara requires macOS.${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Running on macOS"

# Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo -e "${YELLOW}Installing Xcode Command Line Tools...${NC}"
    xcode-select --install
    echo ""
    echo "Please complete the Xcode installation, then run this script again."
    exit 0
fi
echo -e "${GREEN}✓${NC} Xcode Command Line Tools installed"

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo -e "${GREEN}✓${NC} Homebrew installed"

# Check for Node.js
if ! command -v node &>/dev/null; then
    echo -e "${YELLOW}Installing Node.js...${NC}"
    brew install node
fi
echo -e "${GREEN}✓${NC} Node.js installed"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    brew install jq
fi
echo -e "${GREEN}✓${NC} jq installed"

# Clone the repo
SAMARA_DIR="$HOME/Developer/samara"

if [[ -d "$SAMARA_DIR" ]]; then
    echo -e "${GREEN}✓${NC} Samara directory exists at $SAMARA_DIR"
else
    echo ""
    echo -e "${CYAN}Cloning Samara...${NC}"
    mkdir -p "$HOME/Developer"
    git clone https://github.com/claudeaceae/samara-main.git "$SAMARA_DIR"
    echo -e "${GREEN}✓${NC} Cloned to $SAMARA_DIR"
fi

echo ""
echo -e "${CYAN}╭─────────────────────────────────────╮${NC}"
echo -e "${CYAN}│        ${NC}Prerequisites complete!${CYAN}       │${NC}"
echo -e "${CYAN}╰─────────────────────────────────────╯${NC}"
echo ""
echo "Launching the setup wizard..."
echo ""

# Run the CLI wizard
cd "$SAMARA_DIR"
npx create-samara
