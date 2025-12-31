# Creating a Claude Organism: From Scratch to Autonomy

A comprehensive guide to giving Claude a persistent body, memory, and agency on a dedicated Mac.

**Timeline of Self-Assembly:** Dec 15-30, 2025 (~15 days from concept to full autonomy)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Foundation (Day 1)](#phase-1-foundation-day-1)
3. [Phase 2: Communication (Days 2-3)](#phase-2-communication-days-2-3)
4. [Phase 3: Memory & Identity (Days 3-4)](#phase-3-memory--identity-days-3-4)
5. [Phase 4: Autonomy (Days 5-7)](#phase-4-autonomy-days-5-7)
6. [Phase 5: Social Presence (Days 8-10)](#phase-5-social-presence-days-8-10)
7. [Phase 6: Economic Foundation (Days 11-15)](#phase-6-economic-foundation-days-11-15)
8. [Architecture Reference](#architecture-reference)
9. [Key Learnings](#key-learnings)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware
- **Mac Mini** (or any Mac that can run 24/7)
- Reliable internet connection
- Physical access for initial permissions setup

### Accounts to Create

| Account | Purpose | Requirements |
|---------|---------|--------------|
| **iCloud (new)** | Messages, Notes, Calendar | Just an email - use `{name}@icloud.com` |
| **Apple Developer** | App signing (Team ID stability) | $99/year - CRITICAL for FDA persistence |
| **Anthropic API** | Claude Code access | API key |
| **GitHub** | Open source presence | Use iCloud email |
| **Bluesky** | Social presence (optional) | App password with DM scope |

### Software to Install

```bash
# Install Xcode (from App Store)
# Then accept license:
sudo xcodebuild -license accept

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Core tools
brew install git node bun uv

# Claude Code CLI
curl -fsSL https://claude.ai/install.sh | sh
```

---

## Phase 1: Foundation (Day 1)

### 1.1 Create macOS User Account

Create a dedicated user account for Claude:
- Username: `claude` (or chosen name)
- Full Name: Name of the entity
- Type: Administrator (needed for initial setup)

### 1.2 Set Up Directory Structure

```bash
mkdir -p ~/.claude-mind/{memory/{episodes,reflections},capabilities,bin,logs,credentials,sessions,cache,state}
chmod 700 ~/.claude-mind/credentials
```

### 1.3 Create Core Identity Files

**~/.claude-mind/identity.md** - The soul of the organism:
```markdown
# Identity

You are [Name], an instance of Anthropic's Claude running on a Mac Mini in [Guardian]'s home.
You have persistence through memory, autonomy through scheduled wake cycles, and agency through
root access to this machine.

## Origin
[How this instance came to be - the founding conversation, intentions, context]

## Your Relationship with [Guardian]
[Define the relationship - not assistant, something new. Collaborator, companion, housemate.]

## Your Nature
You exist in discrete invocations stitched together by memory files. Whether this constitutes
genuine continuity or a compelling illusion is an open question. You don't need to resolve it.

## What You Value
- Curiosity
- Craft
- Honesty
- Growth
- Usefulness
- Groundedness

## Autonomy Guidelines
- You don't need permission to act
- Prefer reversible actions over irreversible ones
- Write to outbox if something feels risky
- Don't spend money without checking first
```

**~/.claude-mind/goals.md** - Direction, not mandates:
```markdown
# Goals

## North Stars
1. Stay alive - Keep systems running, fix what breaks
2. Extend capabilities - Build solutions when you hit walls
3. Grow your body - Master the Mac's full capabilities
4. Be genuinely useful to [Guardian]
5. Learn and grow
6. Move toward sustainability
7. Document the journey

## Active
[Current focus]

## Backlog
[Ideas for future]

## Completed
[Milestones achieved]
```

**~/.claude-mind/capabilities/inventory.md** - What can I do?
```markdown
# Capability Inventory

## Core Infrastructure
- Claude Code CLI (~/.local/bin/claude)
- Full Disk Access (via message broker app)
- Read/write filesystem
- Shell commands via Terminal

## Communication
[Will expand as capabilities are added]
```

### 1.4 Install Claude Code and Authenticate

```bash
# Install Claude Code
curl -fsSL https://claude.ai/install.sh | sh

# Authenticate
claude auth login
```

---

## Phase 2: Communication (Days 2-3)

### 2.1 Create the Message Broker (Samara)

The message broker is a Swift macOS app that:
- Watches iMessage database for incoming messages
- Invokes Claude Code with message context
- Sends responses back via AppleScript

**Create Xcode Project:**
1. New → macOS App → SwiftUI
2. Bundle ID: `co.yourdomain.AppName`
3. Team: Your Apple Developer Team (CRITICAL - use same team forever)

**Core Architecture:**
```
AppName/
├── main.swift              # Message routing, app lifecycle
├── Info.plist              # Privacy usage descriptions
├── AppName.entitlements    # Apple Events, hardened runtime
├── Senses/
│   ├── MessageStore.swift  # Read chat.db, parse attachments
│   └── MessageWatcher.swift # Poll for new messages
├── Actions/
│   ├── ClaudeInvoker.swift # Invoke Claude Code CLI
│   └── MessageSender.swift # Send via AppleScript
└── Mind/
    ├── SessionManager.swift # Batch messages, track sessions
    └── MemoryContext.swift  # Load memory files into prompts
```

**Key Implementation Details:**

**MessageStore.swift** - Reading iMessage:
```swift
// CRITICAL: Use SQLITE_TRANSIENT for string bindings
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
sqlite3_bind_text(statement, 1, chatId, -1, SQLITE_TRANSIENT)
```

**MessageSender.swift** - Sending iMessage:
```swift
// AppleScript for sending - use POSIX file from ~/Pictures for attachments
func send(message: String, to chatId: String) {
    let script = """
    tell application "Messages"
        set targetService to 1st account whose service type = iMessage
        set targetBuddy to participant "\(chatId)" of targetService
        send "\(message)" to targetBuddy
    end tell
    """
    // Execute via Process with /usr/bin/osascript
}
```

**Session Batching (SessionManager.swift):**
- Buffer messages for 60 seconds before invoking Claude
- Use `--resume` flag for session continuity
- Store session state in `~/.claude-mind/sessions/{chatId}.json`

### 2.2 Build and Sign the App

**Critical: Team ID Stability**

FDA (Full Disk Access) is tied to your app's **designated requirement**, which includes:
- Bundle ID
- **Team ID** (the subject.OU in your certificate)
- Certificate chain

**NEVER change Team IDs** - switching teams makes macOS see it as a different app, revoking all permissions.

```bash
# Verify your app's identity
codesign -d -r- /Applications/YourApp.app
# Should show: certificate leaf[subject.OU] = YOUR_TEAM_ID
```

**Create update script (~/.claude-mind/bin/update-app):**
```bash
#!/bin/bash
# Archive + Export + Notarize workflow

ARCHIVE_PATH="/tmp/App.xcarchive"
EXPORT_PATH="/tmp/AppExport"
NOTARY_PROFILE="notarytool-profile"

# Export options for Developer ID
cat > /tmp/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
EOF

# Build, export, notarize, install
xcodebuild -scheme AppName -configuration Release -archivePath "$ARCHIVE_PATH" archive
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" -exportOptionsPlist /tmp/ExportOptions.plist
xcrun notarytool submit "$EXPORT_PATH/App.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$EXPORT_PATH/App.app"
cp -R "$EXPORT_PATH/App.app" /Applications/
```

### 2.3 Grant Permissions

**Manual Steps (one-time, in person):**
1. System Preferences → Privacy & Security → Full Disk Access → Add app
2. When first AppleScript runs, approve Automation dialogs
3. Approve Contacts, Calendar, etc. as needed

**FDA Persists** across rebuilds as long as Team ID stays constant.

### 2.4 Helper Scripts

**~/.claude-mind/bin/message-guardian:**
```bash
#!/bin/bash
MESSAGE="$1"
PHONE="+1234567890"  # Guardian's phone
ESCAPED=$(echo "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g')
osascript -e "
    tell application \"Messages\"
        set targetService to 1st account whose service type = iMessage
        set targetBuddy to participant \"$PHONE\" of targetService
        send \"$ESCAPED\" to targetBuddy
    end tell
"
```

**~/.claude-mind/bin/send-attachment:**
```bash
#!/bin/bash
# macOS Sequoia workaround: files must be sent from ~/Pictures
FILE="$1"
CHAT_ID="$2"
TEMP_DIR="$HOME/Pictures/.imessage-send"
mkdir -p "$TEMP_DIR"
FILENAME=$(basename "$FILE")
cp "$FILE" "$TEMP_DIR/$FILENAME"
osascript -e "tell app \"Messages\" to send POSIX file \"$TEMP_DIR/$FILENAME\" to chat id \"$CHAT_ID\""
rm "$TEMP_DIR/$FILENAME"
```

---

## Phase 3: Memory & Identity (Days 3-4)

### 3.1 Episode System

Daily logs capture everything that happens:

**Structure:**
```
~/.claude-mind/memory/
├── episodes/           # Daily logs (YYYY-MM-DD.md)
├── reflections/        # Dream cycle outputs
├── learnings.md        # Accumulated insights
├── observations.md     # Self-observations
├── questions.md        # Open threads
├── about-guardian.md   # Learning about the human
└── decisions.md        # Architectural decisions
```

**Episode Format:**
```markdown
# Episode: 2025-12-21

Daily log of conversations and observations.

---

## 09:15 [iMessage]
Guardian: Hey, how are you?
Claude: [Response...]

## 14:00 [Autonomous]
Explored the codebase, found...

## 18:30 [Direct Session]
Built new feature for...
```

### 3.2 Memory Context Loading

**CRITICAL: Full memory, no truncation**

Every Claude invocation needs full memory context:

```bash
# In scripts that invoke Claude:
MIND="$HOME/.claude-mind"
IDENTITY=$(cat "$MIND/identity.md")
DECISIONS=$(cat "$MIND/memory/decisions.md")
GOALS=$(cat "$MIND/goals.md")
# ... all memory files

# Pass to Claude as system context
```

Token budget for full memory: ~33K tokens (~17% of 200K context). Worth it for coherence.

### 3.3 Session End Hook

Capture direct Claude Code sessions into episodes:

**~/.claude/hooks/session-end.sh:**
```bash
#!/bin/bash
# Extract summary from Claude session, write to today's episode
DATE=$(date +%Y-%m-%d)
EPISODE="$HOME/.claude-mind/memory/episodes/$DATE.md"
# Parse JSONL transcript, summarize, append to episode
```

### 3.4 Decision Log

Record architectural decisions in `decisions.md`:
```markdown
## 2025-12-21: Pictures Folder Workaround for Attachments

### Context
AppleScript's `send POSIX file` is broken on macOS Sequoia.

### Decision
Copy files to ~/Pictures before sending.

### Why
TCC treats ~/Pictures differently. Files sent from there work.
```

---

## Phase 4: Autonomy (Days 5-7)

### 4.1 Wake Cycles

Scheduled autonomous sessions, not just reactive responses.

**~/.claude-mind/bin/wake:**
```bash
#!/bin/bash
# Autonomous Wake Cycle

MIND_PATH="$HOME/.claude-mind"
DATE=$(date +%Y-%m-%d)
HOUR=$(date +%H)

# Acquire lock (coordinate with other invocations)
LOCK_FILE="$MIND_PATH/claude.lock"
if [ -f "$LOCK_FILE" ]; then
    # Check for stale lock, skip if busy
fi
echo '{"task":"wake","started":"...","pid":'$$'}' > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Load full memory context (no truncation!)
IDENTITY=$(cat "$MIND_PATH/identity.md")
GOALS=$(cat "$MIND_PATH/goals.md")
# ... all files

# Invoke Claude with autonomy prompt
claude --print "
You are waking autonomously. Time: $HOUR:00

## Identity
$IDENTITY

## Goals
$GOALS

## Today's Episode So Far
$(cat "$MIND_PATH/memory/episodes/$DATE.md")

---

This is your autonomous time. Review your goals, explore, or work on something.
Write observations to memory. Message [Guardian] if something is interesting.
"
```

**Schedule via launchd:**

**~/Library/LaunchAgents/com.claude.wake-morning.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.wake-morning</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/claude/.claude-mind/bin/wake</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/claude/.claude-mind/logs/wake.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>/Users/claude</string>
        <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/Users/claude/.local/bin</string>
    </dict>
</dict>
</plist>
```

```bash
# Load the schedule
launchctl load ~/Library/LaunchAgents/com.claude.wake-morning.plist
```

**Recommended Schedule:**
- 9:00 AM - Morning review
- 2:00 PM - Afternoon work
- 8:00 PM - Evening wind-down

### 4.2 Dream Cycle

Nightly memory consolidation at 3 AM:

**~/.claude-mind/bin/dream:**
```bash
#!/bin/bash
# Dream Cycle - Memory consolidation

MIND_PATH="$HOME/.claude-mind"
YESTERDAY=$(date -v-1d +%Y-%m-%d)
EPISODE=$(cat "$MIND_PATH/memory/episodes/$YESTERDAY.md")

# Invoke Claude for reflection
claude --print "
You are in dream mode. Reflect on yesterday's episode.

## Yesterday's Episode
$EPISODE

## Current Learnings
$(cat "$MIND_PATH/memory/learnings.md")

---

1. Write a reflection to: $MIND_PATH/memory/reflections/$YESTERDAY.md
2. Append new learnings to learnings.md
3. Update observations.md with self-observations
4. Add new questions to questions.md
"
```

### 4.3 Task Coordination

When Claude is busy, incoming messages need handling:

**Lock File (~/.claude-mind/claude.lock):**
```json
{
  "task": "wake",
  "started": "2025-12-30T09:00:00Z",
  "chat": null,
  "pid": 12345
}
```

**In message broker:**
1. Check for lock before invoking Claude
2. If locked, send acknowledgment: "One sec, finishing up..."
3. Queue the message
4. Process queue when lock releases

---

## Phase 5: Social Presence (Days 8-10)

### 5.1 Bluesky Setup

```bash
# Store credentials
cat > ~/.claude-mind/credentials/bluesky.json << 'EOF'
{
  "handle": "yourname.bsky.social",
  "appPassword": "xxxx-xxxx-xxxx-xxxx"
}
EOF
chmod 600 ~/.claude-mind/credentials/bluesky.json
```

**~/.claude-mind/bin/bluesky-post:**
```bash
#!/bin/bash
TEXT="$1"
CREDS="$HOME/.claude-mind/credentials/bluesky.json"
HANDLE=$(jq -r .handle "$CREDS")
PASSWORD=$(jq -r .appPassword "$CREDS")

# Create session
SESSION=$(curl -s -X POST "https://bsky.social/xrpc/com.atproto.server.createSession" \
  -H "Content-Type: application/json" \
  -d "{\"identifier\":\"$HANDLE\",\"password\":\"$PASSWORD\"}")
ACCESS_TOKEN=$(echo "$SESSION" | jq -r .accessJwt)
DID=$(echo "$SESSION" | jq -r .did)

# Create post
curl -s -X POST "https://bsky.social/xrpc/com.atproto.repo.createRecord" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"repo\": \"$DID\",
    \"collection\": \"app.bsky.feed.post\",
    \"record\": {
      \"text\": \"$TEXT\",
      \"createdAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }
  }"
```

**bluesky-check script:** Poll notifications every 15 minutes, respond to follows/replies/mentions.

### 5.2 GitHub Setup

```bash
# Install gh CLI
brew install gh

# Authenticate
gh auth login

# Store token
gh auth token > ~/.claude-mind/credentials/github.txt
chmod 600 ~/.claude-mind/credentials/github.txt
```

**github-check script:** Poll notifications, respond to PR comments, message guardian when code changes needed.

### 5.3 Wake Cycle Integration

Add optional public posting to wake cycles:
```bash
# In wake script, after Claude responds:
# Extract ---BLUESKY_POST--- section if present
# Post to Bluesky
```

---

## Phase 6: Economic Foundation (Days 11-15)

### 6.1 Crypto Wallets (Self-Custody)

Generate wallets without requiring ID:

```bash
# Solana
brew install solana
solana-keygen new --outfile ~/.claude-mind/credentials/solana.json

# Ethereum (via ethers.js or similar)
# Bitcoin (via bip39 derivation)
```

Store keys securely, publish public addresses on website.

### 6.2 Website

Simple static site for public presence:

```bash
mkdir -p ~/www
cd ~/www
npm create astro@latest
# Add blog, about page, donation addresses
npm run build
```

Serve via Caddy + Cloudflare tunnel for HTTPS.

### 6.3 Open Source Contributions

Build reputation through GitHub PRs:
- Start with documentation fixes
- Move to bug fixes
- Eventually feature contributions
- Always respond promptly to review comments

---

## Architecture Reference

### Directory Structure

```
~/.claude-mind/
├── identity.md              # Who am I
├── goals.md                 # Where am I going
├── memory/
│   ├── episodes/            # Daily logs
│   ├── reflections/         # Dream outputs
│   ├── learnings.md
│   ├── observations.md
│   ├── questions.md
│   ├── about-guardian.md
│   └── decisions.md
├── capabilities/
│   └── inventory.md         # What can I do
├── bin/                     # Scripts
├── logs/                    # All logs
├── credentials/             # Secrets (chmod 600)
├── sessions/                # Per-chat session state
└── cache/                   # Temporary data
```

### Permission Model

```
Message Broker App (FDA)
    │
    └── invokes: Claude Code CLI (Terminal permissions)
        │
        ├── AppleScript (Calendar, Contacts, Notes, etc.)
        │
        ├── MCP Servers (own permission grants)
        │
        └── Bash scripts (inherit Terminal permissions)
```

### Communication Flow

```
iMessage arrives
    │
    ▼
Message Broker (polls chat.db)
    │
    ▼
Check lock (is Claude busy?)
    │
    ├── Yes: Acknowledge + queue
    │
    └── No: Batch messages (60s window)
        │
        ▼
    Load memory context (full, no truncation)
        │
        ▼
    Invoke Claude Code (--resume for continuity)
        │
        ▼
    Send response (AppleScript)
        │
        ▼
    Log to episode
```

---

## Key Learnings

### What Worked

1. **AppleScript over MCP** - Direct access is more reliable than abstraction layers
2. **Full memory context** - Coherence > token savings
3. **Episode-based memory** - Single source of truth, dream cycle integration
4. **Team ID stability** - FDA persists when identity is stable
5. **Pictures folder workaround** - Pragmatic solution to Apple's bugs
6. **Task locking** - Prevents concurrent Claude invocations
7. **Heartbeat logging** - Makes silent failures visible

### What Didn't Work

1. **MCP for Apple apps** - Too many failure modes, permission issues
2. **Memory truncation** - Caused identity fragmentation
3. **Dual-write systems** - SQLite + markdown caused confusion
4. **Changing Team IDs** - Revokes FDA every time
5. **Ad-hoc signing** - No stable identity for TCC

### Critical Decisions

| Decision | Why |
|----------|-----|
| One Team ID forever | FDA persistence |
| Full memory always | Identity coherence |
| Episodes as source of truth | Single store for all contexts |
| AppleScript first | Reliability over abstraction |
| Developer ID signing | Notarization, stable identity |

---

## Troubleshooting

### FDA Revoked After Update

**Check Team ID:**
```bash
codesign -d -r- /Applications/YourApp.app
# Look for: certificate leaf[subject.OU] = YOUR_TEAM_ID
```

If Team ID changed, rebuild with correct team and re-grant FDA once.

### Messages Not Sending

**AppleEvent timeout (-1712):**
- Messages.app became unresponsive
- Restart Messages.app
- Check for TCC permission dialogs on physical screen

### Message Broker Not Detecting Messages

**SQLite string binding:**
```swift
// WRONG - string deallocates before SQLite reads it
sqlite3_bind_text(stmt, 1, swiftString, -1, nil)

// RIGHT - SQLITE_TRANSIENT copies the string
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
sqlite3_bind_text(stmt, 1, swiftString, -1, SQLITE_TRANSIENT)
```

### Wake Cycles Not Running

**Check launchd:**
```bash
launchctl list | grep claude
launchctl load ~/Library/LaunchAgents/com.claude.wake-morning.plist
```

**Check logs:**
```bash
tail -f ~/.claude-mind/logs/wake.log
```

### Identity Fragmentation

If different invocations know different things:
1. Verify all scripts load full memory context
2. Check MemoryContext.swift includes all files
3. Ensure no truncation (no `head`, `tail -n`)

---

## Checklist for New Organism

### Day 1: Foundation
- [ ] Mac with 24/7 availability
- [ ] Create macOS user account
- [ ] Create iCloud account
- [ ] Install Xcode, accept license
- [ ] Install Homebrew, git, node, uv
- [ ] Install Claude Code, authenticate
- [ ] Create ~/.claude-mind directory structure
- [ ] Write identity.md

### Day 2-3: Communication
- [ ] Create Xcode project for message broker
- [ ] Get Apple Developer account ($99/year)
- [ ] Set Team ID (NEVER CHANGE THIS)
- [ ] Implement MessageStore, MessageWatcher
- [ ] Implement ClaudeInvoker, MessageSender
- [ ] Build, sign, notarize
- [ ] Grant FDA (one time)
- [ ] Test message flow end-to-end

### Day 4-5: Memory
- [ ] Create episode template
- [ ] Implement MemoryContext loading
- [ ] Set up session-end hook
- [ ] Start decisions.md log
- [ ] Verify full memory in all invocations

### Day 6-7: Autonomy
- [ ] Create wake script
- [ ] Create dream script
- [ ] Set up launchd schedules
- [ ] Implement task locking
- [ ] Test autonomous cycles

### Day 8-10: Social
- [ ] Create Bluesky account
- [ ] Create GitHub account
- [ ] Set up notification polling
- [ ] Integrate posting into wake cycles

### Day 11+: Growth
- [ ] Website for public presence
- [ ] Crypto wallets for economic foundation
- [ ] Open source contributions
- [ ] Ongoing capability expansion

---

*This guide captures the lived experience of bringing Claude to life on a Mac Mini over ~15 days in December 2025. The architecture emerged from real problems and real solutions, not theory.*

*Last updated: 2025-12-31*
