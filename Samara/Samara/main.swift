import Foundation
import AppKit

// Single instance lock - prevent multiple Samara processes
let lockFilePath = MindPaths.statePath("samara.lock")
let lockFileDescriptor = open(lockFilePath, O_WRONLY | O_CREAT, 0o600)
if lockFileDescriptor == -1 || flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
    // Can't use log() here since Logger may not be initialized yet
    print("[Main] Another Samara instance is already running. Exiting.")
    exit(0)
}
// Lock acquired - we're the only instance

// Configuration - loaded from ~/.claude-mind/system/config.json (see Configuration.swift)
let targetPhone = config.collaborator.phone
let targetEmail = config.collaborator.email
let collaboratorName = config.collaborator.name
let features = config.featuresConfig

// Logging is now handled by Logger.swift with log levels and alerting

log("===========================================")
log("  Samara Starting")
log("  Watching for messages from \(collaboratorName)")
log("  With conversation batching + session continuity")
log("===========================================")

// Initialize NSApplication - required for permission dialogs to appear
let app = NSApplication.shared

// Start as regular app (shows in Dock) to allow permission dialogs
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

// Request permissions - dialogs will appear during run loop
log("Requesting permissions (dialogs may appear)...")
PermissionRequester.requestAllPermissions()

// Run the event loop briefly to allow dialogs to process
// This gives 10 seconds for user to respond to dialogs
for _ in 0..<100 {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
}

// Switch to accessory mode (no Dock icon) for daemon operation
app.setActivationPolicy(.accessory)
log("Switched to background mode")

// Initialize components
let store = MessageStore(targetHandles: [targetPhone, targetEmail])
let sender = MessageSender(targetId: targetPhone)
let memoryContext = MemoryContext()
let invoker = ClaudeInvoker(memoryContext: memoryContext)
let episodeLogger = EpisodeLogger()
let locationTracker = LocationTracker()
let contextRouter = ContextRouter(
    timeout: features.smartContextTimeout ?? 5.0,
    enabled: features.smartContext ?? true
)
let contextSelector = ContextSelector(
    memoryContext: memoryContext,
    contextRouter: contextRouter,
    features: features
)

// Unified message bus - all outbound messages go through here for logging
let messageBus = MessageBus(sender: sender, episodeLogger: episodeLogger, collaboratorName: collaboratorName)
let mailStore = MailStore(targetEmails: [targetEmail], accountName: "iCloud")

// Sense router - handles events from satellite services
let senseRouter = SenseRouter(
    invoker: invoker,
    memoryContext: memoryContext,
    episodeLogger: episodeLogger,
    messageBus: messageBus,
    collaboratorName: collaboratorName
)

// Location file watcher - monitors ~/.claude-mind/state/location.json directly
let locationFileWatcher = LocationFileWatcher(
    pollInterval: 5,  // Check every 5 seconds as backup to dispatch source
    onLocationChanged: { update in
        log("[Main] Location update from file: \(update.latitude), \(update.longitude) (wifi: \(update.wifi ?? "none"))")
        MemoryContext.invalidateLocationCache()

        let analysis = locationTracker.processLocation(update)

        if let location = analysis.currentLocation {
            var details = [
                "Location update",
                "address: \(location.address)",
                "lat: \(String(format: "%.5f", location.latitude))",
                "lon: \(String(format: "%.5f", location.longitude))"
            ]
            if let wifi = update.wifi, !wifi.isEmpty, wifi != "null" {
                details.append("wifi: \(wifi)")
            }
            if let speed = update.speed {
                details.append("speed: \(String(format: "%.2f", speed))")
            }
            if let battery = update.battery {
                details.append("battery: \(battery)")
            }
            if !update.motion.isEmpty {
                details.append("motion: " + update.motion.joined(separator: ", "))
            }

            episodeLogger.logSenseEvent(sense: "location", data: details.joined(separator: "\n"))
        }

        if analysis.shouldMessage, let reason = analysis.reason {
            log("[Main] Location trigger: \(reason)")

            // Send proactive message to collaborator via MessageBus (ensures logging)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try messageBus.send(reason, type: .locationTrigger)
                    log("[Main] Sent proactive location message")
                } catch {
                    log("[Main] Failed to send location message: \(error)")
                }
            }
        } else {
            if let loc = analysis.currentLocation {
                log("[Main] Location logged: \(loc.address) (no message triggered)", level: .debug)
            }
        }
    }
)

let personProfileWatcher: PersonProfileWatcher? = (features.smartContext ?? true)
    ? PersonProfileWatcher(onProfilesChanged: {
        MemoryContext.invalidatePersonCaches()
    })
    : nil

// Track messages being processed to avoid duplicates
var processingMessages = Set<Int64>()
let processingLock = NSLock()

// Path to distill-session script
let distillSessionPath = MindPaths.systemPath("bin/distill-session")

// Session manager for batching and continuity
var sessionManager: SessionManager!

// Queue processor for handling messages during busy periods
let queueProcessor = QueueProcessor()

// Permission dialog monitor - alerts collaborator when manual intervention is needed
let permissionMonitor = PermissionDialogMonitor { message in
    // Send alert to collaborator via MessageBus (ensures logging)
    do {
        try messageBus.send(message, type: .alert)
        log("[Main] Sent permission dialog alert: \(message)")
    } catch {
        log("[Main] Failed to send permission dialog alert: \(error)")
    }
}

/// Build an acknowledgment message based on the current task
func buildAcknowledgment() -> String {
    let taskDesc = TaskLock.taskDescription()

    // Playful + informative style per collaborator's preference
    switch TaskLock.currentTask()?.task {
    case "wake":
        return "One sec, wrapping up a wake cycle - got your message though!"
    case "dream":
        return "Hold that thought - in the middle of dreaming. Back shortly!"
    case "message":
        return "Got it! Just finishing up another conversation, be right with you."
    case "bluesky":
        return "One moment - posting something to Bluesky. Back in a sec!"
    case "github":
        return "Hang on, checking GitHub notifications. Got your message!"
    default:
        return "One sec, in the middle of \(taskDesc) - got your message though!"
    }
}

// Batch processing handler - called when buffer timer expires
func handleBatch(messages: [Message], resumeSessionId: String?) {
    guard !messages.isEmpty else { return }

    let chatIdentifier = messages.first?.chatIdentifier ?? ""
    let isGroupChat = messages.first?.isGroupChat ?? false
    let scope = LockScope.conversation(chatIdentifier: chatIdentifier)

    // Check if THIS CHAT is already busy (per-chat locking allows concurrent chats)
    if TaskLock.isLocked(scope: scope) {
        log("[Main] This chat is busy, queueing \(messages.count) message(s) for chat \(chatIdentifier)")

        // Queue silently - no acknowledgment needed for same-chat scenarios.
        // Feels more natural: humans don't say "hold on" for every message.
        // QueueProcessor will pick these up when the current invocation finishes.
        for message in messages {
            MessageQueue.enqueue(message, acknowledged: false)
        }

        return  // Don't invoke Claude now - queue processor will handle it
    }

    // Acquire the lock for this chat specifically
    guard TaskLock.acquire(scope: scope, task: "message") else {
        // Race condition - someone else got the lock between check and acquire
        log("[Main] Failed to acquire lock (race condition), queueing messages")
        for message in messages {
            MessageQueue.enqueue(message)
        }
        return
    }

    log("[Main] Processing batch of \(messages.count) message(s)")
    if let sessionId = resumeSessionId {
        log("[Main] Resuming session: \(sessionId)")
    } else {
        log("[Main] Starting new session")
    }

    // Process in background (capture scope for deferred release)
    let lockScope = scope
    DispatchQueue.global(qos: .userInitiated).async {
        // Always release the lock when done, even on error
        defer { TaskLock.release(scope: lockScope) }

        do {
            // Determine if this is a collaborator-only chat (for privacy filtering)
            let targetHandlesSet = Set([targetPhone, targetEmail])
            let isCollaboratorChat = messages.allSatisfy { msg in
                msg.isFromE(targetHandles: targetHandlesSet)
            } && !(messages.first?.isGroupChat ?? false)

            // Build context from memory (excludes collaborator profile for non-collaborator chats)
            let context = contextSelector.context(for: messages, isCollaboratorChat: isCollaboratorChat)

            // Fetch chat info for group chats (name + participants)
            var chatInfo: ChatInfo? = nil
            if let firstMessage = messages.first, firstMessage.isGroupChat {
                chatInfo = store.fetchChatInfo(chatId: firstMessage.chatId)
                log("[Main] Fetched chat info: name=\(chatInfo?.displayName ?? "none"), participants=\(chatInfo?.participants.count ?? 0)")
            }

            // Invoke Claude with batch
            log("Invoking Claude...")
            let result = try invoker.invokeBatch(
                messages: messages,
                context: context,
                resumeSessionId: resumeSessionId,
                targetHandles: Set([targetPhone, targetEmail]),
                chatInfo: chatInfo
            )
            log("[Main] Got response: \(result.response.prefix(100))...")

            // Send response to appropriate destination
            // All messages in batch are from the same chat, so check the first one
            if let firstMessage = messages.first {
                log("[Main] Routing decision: chatIdentifier=\(firstMessage.chatIdentifier), isGroupChat=\(firstMessage.isGroupChat), sender=\(firstMessage.handleId)")

                // Sanity check: group chat identifiers are 32-char hex, but isGroupChat should be true
                let looksLikeGroupChat = firstMessage.chatIdentifier.count == 32 &&
                    firstMessage.chatIdentifier.allSatisfy { $0.isHexDigit }
                if looksLikeGroupChat && !firstMessage.isGroupChat {
                    log("[Main] WARNING: chatIdentifier looks like group chat but isGroupChat=false! This is a bug.")
                }

                // Route through MessageBus (skip episode log - we'll call logExchange below for full context)
                try messageBus.send(result.response, type: .conversationResponse, chatIdentifier: firstMessage.chatIdentifier, isGroupChat: firstMessage.isGroupChat, skipEpisodeLog: true)
                if firstMessage.isGroupChat {
                    log("[Main] Response sent to group chat \(firstMessage.chatIdentifier)")
                } else {
                    log("[Main] Response sent to \(collaboratorName) directly")
                }
            } else {
                log("[Main] ERROR: No messages in batch!")
            }

            // Get the ROWID of the response we just sent (for read tracking)
            // Use chat-specific lookup to avoid race condition with concurrent sessions
            let responseRowId: Int64?
            if let firstMessage = messages.first {
                responseRowId = store.getLastOutgoingMessageRowId(forChat: firstMessage.chatIdentifier)
            } else {
                responseRowId = store.getLastOutgoingMessageRowId()  // Fallback (shouldn't happen)
            }

            // Update session state with new session ID and response ROWID
            if let sessionId = result.sessionId, let firstMessage = messages.first {
                sessionManager.recordResponse(sessionId: sessionId, responseRowId: responseRowId, forChat: firstMessage.chatIdentifier)
            }

            // Log the exchange to today's episode
            let combinedMessage = messages.map { $0.fullDescription }.joined(separator: "\n---\n")
            episodeLogger.logExchange(from: collaboratorName, message: combinedMessage, response: result.response)

        } catch {
            log("[Main] Error processing batch: \(error)")

            // Try to send error notification via MessageBus (ensures logging)
            do {
                let errorMsg = "Sorry, I encountered an error: \(error)"
                if let firstMessage = messages.first {
                    try messageBus.send(errorMsg, type: .error, chatIdentifier: firstMessage.chatIdentifier, isGroupChat: firstMessage.isGroupChat)
                } else {
                    try messageBus.send(errorMsg, type: .error)
                }
            } catch {
                log("Failed to send error message: \(error)", level: .warn)
            }
        }

        // Clean up processing set
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            processingLock.lock()
            for message in messages {
                processingMessages.remove(message.rowId)
            }
            processingLock.unlock()
        }
    }
}

// Session expiration handler - distill memories from expired session
func handleSessionExpired(sessionId: String, messages: [Message]) {
    log("Session \(sessionId) expired with \(messages.count) message(s), triggering distillation...")

    // Run distillation in background
    DispatchQueue.global(qos: .utility).async {
        // Format messages for distillation
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        var conversationLog = ""
        for message in messages {
            let timestamp = dateFormatter.string(from: message.date)
            conversationLog += "[\(timestamp)] \(collaboratorName): \(message.fullDescription)\n"
        }

        // Skip if no meaningful content
        guard !conversationLog.isEmpty else {
            log("No content to distill, skipping", level: .debug)
            return
        }

        // Invoke distill-session script
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [distillSessionPath, sessionId]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Ensure we clean up file handles even on error
        defer {
            try? inputPipe.fileHandleForReading.close()
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? outputPipe.fileHandleForWriting.close()
        }

        do {
            try process.run()

            // Write conversation to stdin and close write end
            if let data = conversationLog.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                log("Distillation output: \(output)", level: .debug)
            }

            if process.terminationStatus == 0 {
                log("Distillation complete for session \(sessionId)")
            } else {
                log("Distillation failed with status \(process.terminationStatus)", level: .warn)
            }
        } catch {
            log("Failed to run distillation: \(error)", level: .error)
        }
    }
}

// Initialize SessionManager with callbacks
sessionManager = SessionManager(
    onBatchReady: handleBatch,
    checkReadStatus: { rowId in
        guard let status = store.getReadStatus(forRowId: rowId) else {
            return nil
        }
        return SessionManager.ReadStatus(isRead: status.isRead, readTime: status.readTime)
    },
    onSessionExpired: handleSessionExpired
)

// Set up queue processor and start monitoring
queueProcessor.setSessionManager(sessionManager)
queueProcessor.startMonitoring()
log("[Main] Queue processor started")

// Start permission dialog monitor
permissionMonitor.startMonitoring()
log("[Main] Permission dialog monitor started")

// Clean up any stale locks from previous crashes
TaskLock.cleanupStaleLocks()
log("[Main] Cleaned up stale locks")

// Message handler - now routes through SessionManager
func handleMessage(_ message: Message) {
    // Avoid processing the same message twice
    processingLock.lock()
    if processingMessages.contains(message.rowId) {
        processingLock.unlock()
        return
    }
    processingMessages.insert(message.rowId)
    processingLock.unlock()

    // Log what we received
    if message.isReaction {
        log("[Main] Buffering reaction: \(message.fullDescription)")
    } else if message.hasAttachments {
        log("[Main] Buffering message with \(message.attachments.count) attachment(s)")
        for attachment in message.attachments {
            log("[Main]   - \(attachment.mimeType): \(attachment.fileName)")
        }
    } else {
        log("[Main] Buffering message: \(message.text.prefix(50))...")
    }

    // Add to session manager buffer (will be batched and processed after timeout)
    sessionManager.addMessage(message)
}

// Open database connection
do {
    try store.open()
    log("[Main] Database connection opened")
} catch {
    log("[Main] FATAL: Could not open Messages database: \(error)")
    log("[Main] Make sure Terminal/this app has Full Disk Access in System Settings")
    exit(1)
}

// Set up cleanup on exit
signal(SIGINT) { _ in
    log("Shutting down, flushing pending messages...")
    sessionManager.flush()
    exit(0)
}

signal(SIGTERM) { _ in
    log("Shutting down, flushing pending messages...")
    sessionManager.flush()
    exit(0)
}

// Start watching
let watcher = MessageWatcher(store: store, onNewMessage: handleMessage)

do {
    try watcher.start()
} catch {
    log("FATAL: Could not start message watcher: \(error)", level: .error)
    exit(1)
}

// Track last scratchpad processing to prevent feedback loops
// When Claude edits the note, NoteWatcher sees it as a change - we need to ignore our own edits
var lastScratchpadProcessed: Date? = nil
var lastClaudeEditHash: String? = nil  // Hash of content after Claude's edit
let scratchpadCooldown: TimeInterval = 45  // Backup cooldown to prevent rapid feedback loops

/// Append Claude's response to the scratchpad note
/// This keeps editing logic in Samara, not in Claude's response
func appendToScratchpad(noteId: String, noteName: String, response: String, existingHtml: String) {
    // Remove @Claude mentions from existing HTML (case insensitive)
    var cleanedHtml = existingHtml
    let mentionPatterns = ["@Claude", "@claude", "@CLAUDE"]
    for pattern in mentionPatterns {
        cleanedHtml = cleanedHtml.replacingOccurrences(of: pattern, with: "")
    }

    // Convert response to HTML divs
    let responseLines = response.split(separator: "\n", omittingEmptySubsequences: false)
    var responseHtml = "<div><br></div><div>---</div><div><br></div>"  // Separator
    for line in responseLines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            responseHtml += "<div><br></div>"
        } else {
            // Escape HTML special characters
            let escaped = trimmed
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            responseHtml += "<div>\(escaped)</div>"
        }
    }

    // Combine: cleaned existing + Claude's response
    let newHtml = cleanedHtml + responseHtml

    // Escape for AppleScript
    let escapedHtml = newHtml
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    // Build AppleScript
    let noteTarget: String
    if !noteId.isEmpty {
        let escapedId = noteId.replacingOccurrences(of: "\"", with: "\\\"")
        noteTarget = "set targetNote to note id \"\(escapedId)\""
    } else {
        let escapedName = noteName.replacingOccurrences(of: "\"", with: "\\\"")
        noteTarget = "set targetNote to first note whose name is \"\(escapedName)\""
    }

    let script = """
        tell application "Notes"
            \(noteTarget)
            set body of targetNote to "\(escapedHtml)"
        end tell
        """

    // Execute AppleScript
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            log("[Main] Scratchpad updated successfully", level: .info)
        } else {
            log("[Main] Scratchpad update failed (exit \(process.terminationStatus))", level: .warn)
        }
    } catch {
        log("[Main] Error updating scratchpad: \(error)", level: .warn)
    }

    // Record the new hash for feedback loop prevention
    Thread.sleep(forTimeInterval: 0.5)
    if let postEditContent = noteWatcher.checkNote(named: noteName) {
        lastClaudeEditHash = postEditContent.contentHash
        log("[Main] Recorded post-edit hash: \(postEditContent.contentHash)", level: .debug)
    }
}

// Note change handler - invokes Claude when watched notes change
func handleNoteChange(_ update: NoteUpdate) {
    log("[Main] Note changed: '\(update.noteName)' (hash: \(update.contentHash))")

    // For scratchpad updates, invoke Claude to respond
    if update.noteKey == "scratchpad" {
        // Check if this is Claude's own edit (hash match)
        if let claudeHash = lastClaudeEditHash, update.contentHash == claudeHash {
            log("[Main] Scratchpad change ignored - matches Claude's last edit (hash: \(claudeHash))", level: .debug)
            lastClaudeEditHash = nil  // Clear after one match
            return
        }

        // Only respond when explicitly mentioned with @Claude or @claude
        let contentLower = update.plainTextContent.lowercased()
        let hasMention = contentLower.contains("@claude")
        if !hasMention {
            log("[Main] Scratchpad change ignored - no @Claude mention", level: .debug)
            return
        }

        // Check cooldown to prevent feedback loop from our own edits
        if let lastProcessed = lastScratchpadProcessed {
            let elapsed = Date().timeIntervalSince(lastProcessed)
            if elapsed < scratchpadCooldown {
                log("[Main] Scratchpad change ignored - within cooldown (\(Int(elapsed))s < \(Int(scratchpadCooldown))s)", level: .debug)
                return
            }
        }

        log("[Main] Scratchpad @Claude mention detected - processing...")
        lastScratchpadProcessed = Date()  // Record processing time

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let context = contextSelector.context(
                    forText: update.plainTextContent,
                    isCollaboratorChat: true,
                    handleId: targetEmail,
                    chatIdentifier: targetEmail
                )

                let escapedNoteName = update.noteName.replacingOccurrences(of: "\"", with: "\\\"")
                // Claude just generates a response - Samara handles the note editing
                let prompt = """
                    You are Claude, responding to a shared scratchpad note with \(collaboratorName).

                    ## Context
                    \(context)

                    ## Current Scratchpad Content
                    \(update.plainTextContent)

                    ## Instructions
                    \(collaboratorName) mentioned you with @Claude. Respond to whatever they wrote.

                    IMPORTANT: Just write your response text. Do NOT use AppleScript or try to edit the note yourself.
                    Samara will append your response to the note automatically.

                    Keep it casual and concise - this is like passing notes.
                    """

                let result = try invoker.invoke(prompt: prompt, context: "", attachmentPaths: [])
                log("[Main] Scratchpad response: \(result.prefix(100))...")

                // Samara appends Claude's response to the note
                let noteId = update.noteId ?? ""
                appendToScratchpad(noteId: noteId, noteName: update.noteName, response: result, existingHtml: update.htmlContent)

                // Log the exchange
                episodeLogger.logExchange(
                    from: "\(collaboratorName) (Scratchpad)",
                    message: update.plainTextContent.prefix(200).description,
                    response: result,
                    source: "Scratchpad"
                )

            } catch {
                log("[Main] Error processing scratchpad update: \(error)")
            }
        }
    }
}

// Initialize NoteWatcher (for Claude Scratchpad only - location is handled by LocationFileWatcher)
let scratchpadNote = NoteWatcher.WatchedNote(
    key: "scratchpad",
    name: config.notes.scratchpad,
    account: "iCloud",
    folder: "Notes"
)
let noteWatcher = NoteWatcher(
    watchedNotes: [scratchpadNote],
    pollInterval: 15,  // Check every 15 seconds (reduced for snappier detection)
    noteIdStorePath: MindPaths.mindPath("state/note-watcher.json"),
    onNoteChanged: handleNoteChange
)
noteWatcher.start()

personProfileWatcher?.start()

// Start location file watcher (monitors ~/.claude-mind/state/location.json)
locationFileWatcher.start()

// Initialize CaptureRequestWatcher for webcam capture via Claude
// This allows Claude to request photos using Samara's camera permission
let captureWatcher = CaptureRequestWatcher()
captureWatcher.start()
log("[Main] Capture request watcher started")

// Initialize SenseDirectoryWatcher for satellite services
// Watches ~/.claude-mind/senses/ for *.event.json files from satellites
let senseWatcher = SenseDirectoryWatcher(
    pollInterval: 5,  // Check every 5 seconds as backup to dispatch source
    onSenseEvent: { event in
        log("[Main] Sense event received: \(event.sense) (priority: \(event.priority.rawValue))")
        senseRouter.route(event)
    }
)
senseWatcher.start()
log("[Main] Sense directory watcher started")

// Email handler - invokes Claude for emails from collaborator
func handleEmail(_ email: Email) {
    log("[Main] Processing email from \(email.sender): \(email.subject)")

    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let analysisText = """
                Email from \(email.sender)
                Subject: \(email.subject)
                \(email.content)
                """
            let context = contextSelector.context(
                forText: analysisText,
                isCollaboratorChat: true,
                handleId: email.sender,
                chatIdentifier: email.sender
            )

            let prompt = """
                You received an email from \(collaboratorName). Read and respond appropriately.

                ## Email Details
                From: \(email.sender)
                Subject: \(email.subject)
                Date: \(email.date)

                ## Email Content
                \(email.content)

                ## Instructions
                - Respond to the email content
                - Be conversational but appropriate for email
                - If they ask you to text them, send an iMessage using the message script
                - You can reply via email using osascript to send through Mail.app

                To reply via email:
                osascript -e 'tell application "Mail"
                    set newMsg to make new outgoing message with properties {subject:"Re: SUBJECT", content:"YOUR REPLY", visible:false}
                    tell newMsg
                        make new to recipient at end of to recipients with properties {address:"\(targetEmail)"}
                    end tell
                    send newMsg
                end tell'

                To also text \(collaboratorName):
                ~/.claude-mind/system/bin/message "Your message here"
                """

            let result = try invoker.invoke(prompt: prompt, context: context, attachmentPaths: [])
            log("[Main] Email response: \(result.prefix(100))...")

            // Mark the email as read after processing
            try? mailStore.markAsRead(emailId: email.id)

            // Log the exchange
            episodeLogger.logExchange(
                from: "\(collaboratorName) (Email)",
                message: "Subject: \(email.subject)\n\(email.content.prefix(500))",
                response: result,
                source: "Email"
            )

        } catch {
            log("[Main] Error processing email: \(error)")
        }
    }
}

// Initialize MailWatcher
let mailWatcher = MailWatcher(
    store: mailStore,
    pollInterval: 60,  // Check every 60 seconds
    onNewEmail: handleEmail
)
mailWatcher.start()

log("[Main] Samara running. Press Ctrl+C to stop.")
log("[Main] Watching for messages from \(targetPhone) or \(targetEmail)...")
log("[Main] Watching notes: \(scratchpadNote.name)")
log("[Main] Watching location file: \(MindPaths.statePath("location.json"))")
log("[Main] Watching email inbox for messages from \(targetEmail)")
log("[Main] Watching sense directory: \(MindPaths.systemPath("senses"))")

// Keep the app running - use NSApp.run() to properly handle GCD main queue
app.run()
