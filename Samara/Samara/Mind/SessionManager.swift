import Foundation

/// Manages conversation sessions with message batching and session continuity
/// Maintains separate buffers per chat to avoid mixing group and 1:1 messages
final class SessionManager {

    // MARK: - Configuration

    /// How long to wait after the last message before invoking Claude
    private let batchWindowSeconds: TimeInterval = 11

    /// How long a session stays alive after the last response was read
    private let sessionTimeoutSeconds: TimeInterval = 2 * 60 * 60  // 2 hours

    /// Path to session state directory
    private let sessionStateDir: String

    // MARK: - State

    /// Per-chat buffers: chatIdentifier -> buffered messages
    private var chatBuffers: [String: [(message: Message, timestamp: Date)]] = [:]

    /// Per-chat timers: chatIdentifier -> timer
    private var chatTimers: [String: DispatchSourceTimer] = [:]

    /// Per-chat session state: chatIdentifier -> session state
    private var chatSessions: [String: SessionState] = [:]

    /// Per-chat message history for distillation
    private var chatSessionMessages: [String: [Message]] = [:]

    /// Lock for thread safety
    private let lock = NSLock()

    /// Set of chats currently processing (to prevent concurrent batch processing per chat)
    private var processingChats: Set<String> = []

    /// In-memory session cache for reducing filesystem I/O
    private let sessionCache = SessionCache(ttl: 45.0, maxEntries: 100)

    /// Serial queue for timer operations
    private let timerQueue = DispatchQueue(label: "co.organelle.samara.sessionmanager.timer")

    /// Callback when batch is ready to invoke
    private let onBatchReady: ([Message], String?) -> Void

    /// Callback when a session expires (for memory distillation)
    private let onSessionExpired: ((String, [Message]) -> Void)?

    /// Function to check if a message has been read
    private let checkReadStatus: (Int64) -> ReadStatus?

    // MARK: - Types

    struct SessionState: Codable {
        var sessionId: String
        var chatIdentifier: String
        var lastResponseRowId: Int64?
        var lastResponseTime: Date
        var lastReadTime: Date?

        /// Check if session is still valid
        func isValid(sessionTimeout: TimeInterval, currentReadStatus: ReadStatus?) -> Bool {
            // If we have no last response, session is always valid (fresh start)
            guard lastResponseRowId != nil else { return true }

            // If last response hasn't been read yet, session stays alive indefinitely
            guard let readStatus = currentReadStatus, readStatus.isRead else {
                return true
            }

            // Session is valid if read time is within timeout window
            if let readTime = readStatus.readTime {
                return Date().timeIntervalSince(readTime) < sessionTimeout
            }

            // Fallback: use lastReadTime from state if available
            if let lastRead = lastReadTime {
                return Date().timeIntervalSince(lastRead) < sessionTimeout
            }

            return false
        }
    }

    struct ReadStatus {
        let isRead: Bool
        let readTime: Date?
    }

    // MARK: - Initialization

    init(
        sessionStateDir: String = MindPaths.memoryPath("sessions"),
        onBatchReady: @escaping ([Message], String?) -> Void,
        checkReadStatus: @escaping (Int64) -> ReadStatus?,
        onSessionExpired: ((String, [Message]) -> Void)? = nil
    ) {
        self.sessionStateDir = sessionStateDir
        self.onBatchReady = onBatchReady
        self.checkReadStatus = checkReadStatus
        self.onSessionExpired = onSessionExpired

        // Ensure sessions directory exists
        try? FileManager.default.createDirectory(atPath: sessionStateDir, withIntermediateDirectories: true)

        // Load existing session states
        loadAllSessionStates()
    }

    // MARK: - Public Interface

    /// Add a message to the buffer. Will trigger batch processing after the window expires.
    /// Messages are buffered per-chat to avoid mixing group and 1:1 conversations.
    func addMessage(_ message: Message) {
        lock.lock()
        defer { lock.unlock() }

        let chatId = message.chatIdentifier
        log("Buffering message for chat \(chatId) (isGroupChat=\(message.isGroupChat)): \(message.text.prefix(50))...", level: .debug, component: "SessionManager")

        // Add to per-chat buffer
        if chatBuffers[chatId] == nil {
            chatBuffers[chatId] = []
        }
        chatBuffers[chatId]!.append((message: message, timestamp: Date()))

        // Reset the batch timer for this specific chat
        resetBatchTimer(forChat: chatId)
    }

    /// Get the current session ID for a specific chat if session is still valid
    func getCurrentSessionId(forChat chatIdentifier: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let state = chatSessions[chatIdentifier] else { return nil }

        // Check read status of last response
        var readStatus: ReadStatus? = nil
        if let rowId = state.lastResponseRowId {
            readStatus = checkReadStatus(rowId)
        }

        if state.isValid(sessionTimeout: sessionTimeoutSeconds, currentReadStatus: readStatus) {
            return state.sessionId
        }

        return nil
    }

    /// Update session state after Claude responds for a specific chat
    func recordResponse(sessionId: String, responseRowId: Int64?, forChat chatIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }

        chatSessions[chatIdentifier] = SessionState(
            sessionId: sessionId,
            chatIdentifier: chatIdentifier,
            lastResponseRowId: responseRowId,
            lastResponseTime: Date(),
            lastReadTime: nil
        )

        saveSessionState(forChat: chatIdentifier)
        log("Recorded session \(sessionId) for chat \(chatIdentifier), response ROWID: \(responseRowId ?? -1)", level: .info, component: "SessionManager")
    }

    /// Clear the session for a specific chat
    func clearSession(forChat chatIdentifier: String, triggerDistillation: Bool = false) {
        lock.lock()

        let oldSessionId = chatSessions[chatIdentifier]?.sessionId
        let messagesToDistill = triggerDistillation ? (chatSessionMessages[chatIdentifier] ?? []) : []

        chatSessions.removeValue(forKey: chatIdentifier)
        chatSessionMessages.removeValue(forKey: chatIdentifier)

        let statePath = sessionStatePath(forChat: chatIdentifier)
        try? FileManager.default.removeItem(atPath: statePath)

        // Invalidate cache
        sessionCache.invalidateSync(chatIdentifier)
        log("Session cleared for chat \(chatIdentifier)", level: .info, component: "SessionManager")

        lock.unlock()

        // Trigger distillation outside lock if requested
        if triggerDistillation, let sessionId = oldSessionId, !messagesToDistill.isEmpty {
            log("Triggering distillation for cleared session \(sessionId)", level: .info, component: "SessionManager")
            onSessionExpired?(sessionId, messagesToDistill)
        }
    }

    /// Flush any pending messages immediately (for shutdown)
    func flush() {
        lock.lock()

        // Cancel all timers
        for (_, timer) in chatTimers {
            timer.cancel()
        }
        chatTimers.removeAll()

        // Collect all pending messages by chat
        let pendingChats = chatBuffers
        chatBuffers.removeAll()

        // Add messages to session tracking before unlocking
        for (chatId, bufferedMessages) in pendingChats {
            let messages = bufferedMessages.map { $0.message }
            if messages.isEmpty { continue }

            if chatSessionMessages[chatId] == nil {
                chatSessionMessages[chatId] = []
            }
            chatSessionMessages[chatId]!.append(contentsOf: messages)
        }

        lock.unlock()

        // Process each chat's pending messages
        for (chatId, bufferedMessages) in pendingChats {
            let messages = bufferedMessages.map { $0.message }
            if messages.isEmpty { continue }

            let sessionId = getCurrentSessionId(forChat: chatId)
            log("Flushing \(messages.count) buffered message(s) for chat \(chatId)", level: .info, component: "SessionManager")
            onBatchReady(messages, sessionId)
        }
    }

    // MARK: - Private Methods

    private func resetBatchTimer(forChat chatIdentifier: String) {
        timerQueue.async { [weak self] in
            guard let self = self else { return }

            // Cancel existing timer for this chat
            self.lock.lock()
            self.chatTimers[chatIdentifier]?.cancel()
            self.chatTimers.removeValue(forKey: chatIdentifier)
            self.lock.unlock()

            // Create new timer for this chat
            let timer = DispatchSource.makeTimerSource(queue: self.timerQueue)
            timer.schedule(deadline: .now() + self.batchWindowSeconds)
            timer.setEventHandler { [weak self] in
                self?.processBatch(forChat: chatIdentifier)
            }
            timer.resume()

            self.lock.lock()
            self.chatTimers[chatIdentifier] = timer
            self.lock.unlock()

            log("Batch timer reset for chat \(chatIdentifier), will fire in \(Int(self.batchWindowSeconds))s", level: .debug, component: "SessionManager")
        }
    }

    private func processBatch(forChat chatIdentifier: String) {
        lock.lock()

        // Prevent concurrent batch processing for this chat
        if processingChats.contains(chatIdentifier) {
            log("Batch already processing for chat \(chatIdentifier), skipping", level: .debug, component: "SessionManager")
            lock.unlock()
            return
        }

        // Check if there are messages for this chat
        guard let bufferedMessages = chatBuffers[chatIdentifier], !bufferedMessages.isEmpty else {
            log("No messages in buffer for chat \(chatIdentifier), skipping", level: .debug, component: "SessionManager")
            lock.unlock()
            return
        }

        processingChats.insert(chatIdentifier)
        chatTimers[chatIdentifier]?.cancel()
        chatTimers.removeValue(forKey: chatIdentifier)

        let messages = bufferedMessages.map { $0.message }
        chatBuffers.removeValue(forKey: chatIdentifier)

        // Determine if we should resume existing session for this chat
        var sessionId: String? = nil
        var expiredSessionId: String? = nil
        var expiredSessionMessages: [Message] = []

        if let state = chatSessions[chatIdentifier] {
            var readStatus: ReadStatus? = nil
            if let rowId = state.lastResponseRowId {
                readStatus = checkReadStatus(rowId)
            }

            if state.isValid(sessionTimeout: sessionTimeoutSeconds, currentReadStatus: readStatus) {
                sessionId = state.sessionId
                log("Resuming session \(state.sessionId) for chat \(chatIdentifier)", level: .info, component: "SessionManager")
            } else {
                log("Session expired for chat \(chatIdentifier), starting fresh", level: .info, component: "SessionManager")
                // Capture expired session info for distillation
                expiredSessionId = state.sessionId
                expiredSessionMessages = chatSessionMessages[chatIdentifier] ?? []
                // Clear state for new session
                chatSessions.removeValue(forKey: chatIdentifier)
                chatSessionMessages.removeValue(forKey: chatIdentifier)
                saveSessionState(forChat: chatIdentifier)
            }
        }

        // Add current messages to session tracking for this chat
        if chatSessionMessages[chatIdentifier] == nil {
            chatSessionMessages[chatIdentifier] = []
        }
        chatSessionMessages[chatIdentifier]!.append(contentsOf: messages)

        lock.unlock()

        // Trigger distillation for expired session (outside lock)
        if let expiredId = expiredSessionId, !expiredSessionMessages.isEmpty {
            log("Triggering distillation for expired session \(expiredId)", level: .info, component: "SessionManager")
            onSessionExpired?(expiredId, expiredSessionMessages)
        }

        // Debug: log message details
        for (idx, msg) in messages.enumerated() {
            log("Message[\(idx)]: chatIdentifier=\(msg.chatIdentifier), isGroupChat=\(msg.isGroupChat), sender=\(msg.handleId)", level: .debug, component: "SessionManager")
        }
        log("Processing batch of \(messages.count) message(s) for chat \(chatIdentifier)", level: .info, component: "SessionManager")
        onBatchReady(messages, sessionId)

        // Mark batch processing complete for this chat
        lock.lock()
        processingChats.remove(chatIdentifier)
        lock.unlock()
    }

    private func sessionStatePath(forChat chatIdentifier: String) -> String {
        // Create a safe filename from chat identifier
        let safeId = chatIdentifier.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ";", with: "_")
        return "\(sessionStateDir)/\(safeId).json"
    }

    private func loadAllSessionStates() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionStateDir) else {
            return
        }

        for file in files where file.hasSuffix(".json") {
            let path = "\(sessionStateDir)/\(file)"
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let state = try JSONDecoder().decode(SessionState.self, from: data)
                chatSessions[state.chatIdentifier] = state
                // Also populate cache
                sessionCache.setSync(state.chatIdentifier, state: state)
                log("Loaded session state for chat \(state.chatIdentifier): \(state.sessionId)", level: .debug, component: "SessionManager")
            } catch {
                log("Failed to load session state from \(file): \(error)", level: .warn, component: "SessionManager")
                // Backup corrupted file and continue
                backupCorruptedFile(at: path, filename: file)
            }
        }
        log("Loaded \(chatSessions.count) session states into memory and cache", level: .info, component: "SessionManager")
    }

    /// Backup a corrupted session state file for debugging
    private func backupCorruptedFile(at path: String, filename: String) {
        let backupDir = "\(sessionStateDir)/corrupted"
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(backupDir)/\(timestamp)-\(filename)"

        do {
            try FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(atPath: path, toPath: backupPath)
            log("Backed up corrupted session state to \(backupPath)", level: .warn, component: "SessionManager")
        } catch {
            // If backup fails, just delete the corrupted file
            try? FileManager.default.removeItem(atPath: path)
            log("Removed corrupted session state (backup failed): \(filename)", level: .warn, component: "SessionManager")
        }
    }

    /// Save session state with atomic write and retry
    private func saveSessionState(forChat chatIdentifier: String) {
        let path = sessionStatePath(forChat: chatIdentifier)
        let url = URL(fileURLWithPath: path)

        guard let state = chatSessions[chatIdentifier] else {
            // No state to save - remove the file and invalidate cache
            try? FileManager.default.removeItem(atPath: path)
            sessionCache.invalidateSync(chatIdentifier)
            return
        }

        // Update cache immediately
        sessionCache.setSync(chatIdentifier, state: state)

        let backoff = Backoff(config: Backoff.Config(
            maxRetries: 3,
            baseDelay: 0.1,
            maxDelay: 1.0,
            multiplier: 2.0,
            jitter: 0.05
        ))

        do {
            try backoff.execute(
                operation: {
                    let data = try JSONEncoder().encode(state)
                    // .atomic option handles temp file + rename internally
                    try data.write(to: url, options: .atomic)
                },
                onRetry: { attempt, delay, error in
                    log("Retrying session state save for \(chatIdentifier) (attempt \(attempt))", level: .warn, component: "SessionManager")
                }
            )
        } catch {
            log("Failed to save session state for chat \(chatIdentifier) after retries: \(error)", level: .error, component: "SessionManager")
        }
    }
}
