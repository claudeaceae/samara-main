# Xcode Build Guide

Samara.app project structure, build workflow, and Full Disk Access management.

> **Back to:** [CLAUDE.md](../CLAUDE.md) | [Documentation Index](INDEX.md)

---

## Xcode Project Structure

```
Samara/
├── Samara.xcodeproj
├── ExportOptions.plist
├── Samara.entitlements
└── Samara/
    ├── main.swift              # Message routing
    ├── Configuration.swift     # Loads config.json
    ├── PermissionRequester.swift
    ├── Logger.swift
    ├── Backoff.swift           # Exponential backoff (Phase 1)
    ├── Info.plist
    ├── Senses/
    │   ├── MessageStore.swift  # Reads chat.db
    │   ├── MessageWatcher.swift
    │   ├── MailStore.swift
    │   ├── MailWatcher.swift
    │   ├── NoteWatcher.swift
    │   ├── ContactsResolver.swift
    │   ├── CameraCapture.swift
    │   ├── LocationFileWatcher.swift
    │   ├── SenseEvent.swift        # Sense event schema (Phase 4)
    │   └── SenseDirectoryWatcher.swift  # Watches ~/.claude-mind/senses/
    ├── Actions/
    │   ├── ClaudeInvoker.swift     # Invokes Claude Code
    │   ├── MessageSender.swift
    │   ├── MessageBus.swift        # Unified output channel
    │   ├── ModelFallbackChain.swift    # Multi-tier fallback (Phase 1)
    │   ├── LocalModelInvoker.swift     # Ollama integration (Phase 1)
    │   └── ReverseGeocoder.swift
    └── Mind/
        ├── SessionManager.swift
        ├── SessionCache.swift      # Session caching (Phase 1)
        ├── TaskLock.swift
        ├── MessageQueue.swift
        ├── QueueProcessor.swift
        ├── MemoryContext.swift
        ├── MemoryDatabase.swift    # SQLite + FTS5 (Phase 2)
        ├── LedgerManager.swift     # Structured handoffs (Phase 2)
        ├── ContextTracker.swift    # Context warnings (Phase 2)
        ├── EpisodeLogger.swift
        ├── TaskRouter.swift        # Parallel task isolation
        ├── LocationTracker.swift
        ├── ContextTriggers.swift   # Proactive triggers (Phase 3)
        ├── ProactiveQueue.swift    # Message pacing (Phase 3)
        ├── VerificationService.swift   # Local model verification (Phase 3)
        ├── RitualLoader.swift      # Wake-type context (Phase 4)
        ├── SenseRouter.swift       # Routes sense events (Phase 4)
        └── PermissionDialogMonitor.swift
```

---

## Response Sanitization (Critical)

In complex group chat scenarios with multiple concurrent requests (webcam + web fetch + conversation), internal thinking traces and session IDs can leak into user-visible messages. This was discovered on 2026-01-05 when session IDs like `1767301033-68210` appeared in messages.

### Three-Layer Defense

1. **Output Sanitization** (`ClaudeInvoker.swift`):
   - `sanitizeResponse()` strips internal content before any message is sent
   - Filters: `<thinking>` blocks, session ID patterns, XML markers
   - Filtered content is logged at DEBUG level for diagnosis
   - **Critical**: `parseJsonOutput()` never falls back to raw output

2. **MessageBus Coordination** (`MessageBus.swift`):
   - ALL outbound messages route through single channel
   - Source tags (iMessage, Location, Wake, Alert) added to episode logs
   - Prevents uncoordinated fire-and-forget sends

3. **TaskRouter Isolation** (`TaskRouter.swift`):
   - Classifies batched messages by task type
   - Isolates webcam/web fetch/skill tasks from conversation session
   - Prevents cross-contamination between concurrent streams

### Testing

Run `SamaraTests/SanitizationTests.swift` to verify sanitization logic.

### If leaks recur

1. Check `~/.claude-mind/logs/samara.log` for "Filtered from response" DEBUG entries
2. Verify MessageBus is used for all sends (no direct `sender.send()` calls)
3. Consider if new task types need classification in TaskRouter

---

## Build Workflow

> **CRITICAL WARNING**: ALWAYS use the update-samara script. NEVER copy from DerivedData.
> A previous Claude instance broke FDA by copying a Debug build from DerivedData.
> This used the wrong signing certificate and revoked all permissions.

### The ONLY correct way to rebuild Samara:

```bash
~/.claude-mind/bin/update-samara
```

This script handles:
1. Archive with Release configuration
2. Export with Developer ID signing (Team G4XVD3J52J)
3. Notarization and stapling
4. Safe installation to /Applications

### FORBIDDEN actions (will break FDA):

- `cp -R ~/Library/Developer/Xcode/DerivedData/.../Samara.app /Applications/`
- `xcodebuild -configuration Debug` for deployment
- Any manual copy of Samara.app to /Applications

### Verify after rebuild:

```bash
codesign -d -r- /Applications/Samara.app 2>&1 | grep "subject.OU"
# Must show: G4XVD3J52J (NOT 7V9XLQ8YNQ)
```

---

## FDA Persistence

Full Disk Access is tied to the app's **designated requirement**:
- Bundle ID
- Team ID (must be G4XVD3J52J)
- Certificate chain

### FDA persists across rebuilds if:

- Team ID stays constant
- Using `update-samara` script

### FDA gets revoked if:

- Team ID changes (e.g., using wrong certificate)
- Ad-hoc signing is used
- Copying from DerivedData (uses automatic signing)
- Bundle ID changes

---

## TCC Permissions Note

Some capabilities require native implementation in Samara.app rather than scripts:

- **Camera**: Uses `CameraCapture.swift` (AVFoundation) because subprocess permission inheritance doesn't work
- **Screen Recording**: Would need similar native implementation
- **Microphone**: Would need similar native implementation

If a script needs a TCC-protected resource and fails when invoked via Samara, the solution is native implementation in Samara with file-based IPC, not trying to grant permissions to subprocesses.
