# Setup Guide

Complete setup walkthrough for new Samara organisms.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Prerequisites

```bash
# Check for required tools
xcode-select -p          # Xcode Command Line Tools
which jq                 # JSON parsing (brew install jq)
which claude             # Claude Code CLI
```

**Required accounts:**
- iCloud account for the Claude instance (for Messages, Notes)
- Apple Developer account ($99/year) for app signing - needed for Full Disk Access persistence

---

## Step 1: Configure

```bash
# Copy and edit configuration
cp config.example.json my-config.json
# Edit my-config.json with collaborator's details
```

The config defines:
- `entity` — Claude's identity (name, iCloud, Bluesky, GitHub)
- `collaborator` — The human partner (name, phone, email, Bluesky)

---

## Step 2: Run Birth Script

```bash
./birth.sh my-config.json
```

This creates:
- `~/.claude-mind/` directory structure
- Identity, goals, and capability files from templates
- Scripts in `bin/`
- launchd plist templates
- **Claude Code settings** (`~/.claude/settings.json`) with 100-year session retention

---

## Step 3: Build Samara.app

The message broker app is in `Samara/`:

```bash
cd Samara

# Open in Xcode to set up signing
open Samara.xcodeproj

# In Xcode:
# 1. Select your Apple Developer Team
# 2. Update Bundle ID if needed (e.g., com.yourname.Samara)
# 3. Archive and Export (Product → Archive)
# 4. Move to /Applications

# Or use command line after Xcode setup:
xcodebuild -scheme Samara -configuration Release archive -archivePath /tmp/Samara.xcarchive
xcodebuild -exportArchive -archivePath /tmp/Samara.xcarchive -exportPath /tmp/SamaraExport -exportOptionsPlist Samara/ExportOptions.plist
cp -R /tmp/SamaraExport/Samara.app /Applications/
```

**CRITICAL:** Note your Team ID. Never change it — FDA persistence depends on stable identity.

For detailed build information, see [Xcode Build Guide](xcode-build-guide.md).

---

## Step 4: Grant Permissions

1. **Full Disk Access** for Samara.app:
   - System Settings → Privacy & Security → Full Disk Access
   - Add `/Applications/Samara.app`

2. **Automation** permissions — approve dialogs on first use

---

## Step 5: Install launchd Services

```bash
cp ~/.claude-mind/launchd/*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude.wake-adaptive.plist
launchctl load ~/Library/LaunchAgents/com.claude.dream.plist
```

---

## Step 6: Launch

```bash
open /Applications/Samara.app
```

Send a test message from the collaborator's phone!

---

## First-Run Verification

After setup, verify everything is working:

```bash
# Check Samara is running
pgrep -fl Samara

# Check launchd services
launchctl list | grep claude

# Verify FDA is working (should list files)
ls ~/.claude-mind/

# Check wake cycle log
tail ~/.claude-mind/logs/wake.log
```

If issues arise, see [Troubleshooting](troubleshooting.md).
