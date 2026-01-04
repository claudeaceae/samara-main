import Foundation

/// Watches the Messages database for new messages and triggers a callback
final class MessageWatcher {
    private let store: MessageStore
    private var lastRowId: Int64 = 0
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let onNewMessage: (Message) -> Void

    /// Poll interval as backup when file watching doesn't trigger
    private let pollInterval: TimeInterval = 5.0
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "samara.poll", qos: .userInitiated)

    /// Lock to prevent concurrent message checking
    private let checkLock = NSLock()

    /// Flag to prevent re-entrant checking
    private var isChecking = false

    /// Error recovery state
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 10
    private var lastAlertTime: Date?
    private let alertCooldown: TimeInterval = 300  // 5 minutes between alerts

    init(store: MessageStore, onNewMessage: @escaping (Message) -> Void) {
        self.store = store
        self.onNewMessage = onNewMessage
    }

    /// Starts watching for new messages
    func start() throws {
        // Get the starting point (latest message ID) with retry
        let backoff = Backoff.forDatabase()
        do {
            lastRowId = try backoff.execute(
                operation: { try store.getLatestRowId() },
                onRetry: { attempt, delay, error in
                    log("Failed to get latest ROWID, retrying in \(Int(delay))s (attempt \(attempt))", level: .warn, component: "MessageWatcher")
                }
            )
        } catch {
            log("Failed to get latest ROWID after retries: \(error)", level: .error, component: "MessageWatcher")
            throw error
        }
        log("Starting from ROWID: \(lastRowId)", level: .info, component: "MessageWatcher")

        // Set up file system watching
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path

        fileDescriptor = open(dbPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw MessageWatcherError.cannotOpenFile
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.checkForNewMessages()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()

        log("Watching for new messages...", level: .info, component: "MessageWatcher")

        // Do an immediate synchronous check
        log("Doing initial check...", level: .info, component: "MessageWatcher")
        checkForNewMessages()
        log("Initial check complete", level: .info, component: "MessageWatcher")

        // Start a background thread for polling
        let watcher = self
        let interval = self.pollInterval
        let thread = Thread {
            while true {
                Thread.sleep(forTimeInterval: interval)
                watcher.checkForNewMessages()
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        log("Poll thread started", level: .info, component: "MessageWatcher")
    }

    /// Stops watching
    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// Checks for new messages since last check
    private func checkForNewMessages() {
        // Prevent concurrent checking
        checkLock.lock()
        if isChecking {
            checkLock.unlock()
            return
        }
        isChecking = true
        let currentLastRowId = lastRowId
        checkLock.unlock()

        do {
            let messages = try store.fetchNewMessages(since: currentLastRowId)

            // Reset failure counter on success
            checkLock.lock()
            consecutiveFailures = 0
            checkLock.unlock()

            if !messages.isEmpty {
                log("Found \(messages.count) new message(s) since ROWID \(currentLastRowId)", level: .info, component: "MessageWatcher")
            }

            checkLock.lock()
            for message in messages {
                // Only process if we haven't already moved past this message
                if message.rowId > lastRowId {
                    log("New message from \(message.handleId): \(message.text.prefix(50))...", level: .info, component: "MessageWatcher")
                    lastRowId = message.rowId
                    checkLock.unlock()
                    onNewMessage(message)
                    checkLock.lock()
                }
            }
            isChecking = false
            checkLock.unlock()
        } catch {
            handleCheckError(error)
        }
    }

    /// Handle errors during message checking with escalation
    private func handleCheckError(_ error: Error) {
        checkLock.lock()
        consecutiveFailures += 1
        let failures = consecutiveFailures
        isChecking = false
        checkLock.unlock()

        // Log with increasing severity based on failure count
        if failures <= 3 {
            log("Error checking messages (attempt \(failures)): \(error)", level: .warn, component: "MessageWatcher")
        } else {
            log("Persistent error checking messages (attempt \(failures)): \(error)", level: .error, component: "MessageWatcher")
        }

        // Alert after threshold reached (with cooldown to prevent spam)
        if failures >= maxConsecutiveFailures {
            let shouldAlert: Bool
            checkLock.lock()
            if let lastAlert = lastAlertTime {
                shouldAlert = Date().timeIntervalSince(lastAlert) > alertCooldown
            } else {
                shouldAlert = true
            }
            if shouldAlert {
                lastAlertTime = Date()
            }
            checkLock.unlock()

            if shouldAlert {
                alertCriticalFailure("MessageWatcher has failed \(failures) times in a row: \(error)", component: "MessageWatcher")
            }
        }

        // Add backoff delay based on failure count to avoid hammering a broken database
        let backoffDelay = min(Double(failures) * 0.5, 5.0)  // Max 5 second delay
        if backoffDelay > 0 {
            Thread.sleep(forTimeInterval: backoffDelay)
        }
    }
}

enum MessageWatcherError: Error {
    case cannotOpenFile
}
