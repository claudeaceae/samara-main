import Foundation

/// Watches the Messages database for new messages and triggers a callback
final class MessageWatcher {
    private let store: MessageStore
    private let watchPath: String
    private let enableFileWatcher: Bool
    private let enablePolling: Bool
    private let initialRowIdOverride: Int64?
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

    /// Thread management (matching MailWatcher pattern)
    private var watchThread: Thread?
    private var shouldStop = false

    /// State persistence for ROWID recovery across restarts
    private let stateFilePath = MindPaths.mindPath("state/message-watcher-state.json")

    private struct WatcherState: Codable {
        var lastRowId: Int64
        var lastSaveTime: Date
    }

    /// Recently processed ROWIDs to prevent duplicates (additional layer beyond isChecking)
    /// This catches race conditions where two threads query the DB before either updates lastRowId
    private var recentlyProcessedRowIds = Set<Int64>()
    private let maxRecentRowIds = 100  // Keep last 100 to prevent memory growth

    init(
        store: MessageStore,
        onNewMessage: @escaping (Message) -> Void,
        initialRowId: Int64? = nil,
        watchPath: String? = nil,
        enableFileWatcher: Bool = true,
        enablePolling: Bool = true
    ) {
        self.store = store
        self.onNewMessage = onNewMessage
        self.initialRowIdOverride = initialRowId
        self.watchPath = watchPath ?? store.dbPath
        self.enableFileWatcher = enableFileWatcher
        self.enablePolling = enablePolling
        if let initialRowId {
            self.lastRowId = initialRowId
        }
    }

    // MARK: - State Persistence

    /// Save current ROWID to disk for recovery after restart
    private func saveState() {
        let state = WatcherState(lastRowId: lastRowId, lastSaveTime: Date())
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
        } catch {
            log("Failed to save watcher state: \(error)", level: .warn, component: "MessageWatcher")
        }
    }

    /// Load persisted ROWID from disk
    private func loadState() -> Int64? {
        guard FileManager.default.fileExists(atPath: stateFilePath) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let state = try JSONDecoder().decode(WatcherState.self, from: data)
            return state.lastRowId
        } catch {
            log("Failed to load watcher state, starting fresh: \(error)", level: .warn, component: "MessageWatcher")
            return nil
        }
    }

    // MARK: - Lifecycle

    /// Starts watching for new messages
    func start() throws {
        if let initialRowId = initialRowIdOverride {
            lastRowId = initialRowId
            log("Starting from overridden ROWID: \(lastRowId)", level: .info, component: "MessageWatcher")
        } else if let savedRowId = loadState() {
            // Resume from saved state (e.g., after restart)
            lastRowId = savedRowId
            // Check how many messages we may have missed
            let backoff = Backoff.forDatabase()
            if let currentMax = try? backoff.execute(operation: { try store.getLatestRowId() }, onRetry: { _, _, _ in }) {
                let missed = currentMax - savedRowId
                if missed > 0 {
                    log("Resuming from saved ROWID \(savedRowId) - \(missed) message(s) pending", level: .info, component: "MessageWatcher")
                } else {
                    log("Resuming from saved ROWID: \(savedRowId)", level: .info, component: "MessageWatcher")
                }
            } else {
                log("Resuming from saved ROWID: \(savedRowId)", level: .info, component: "MessageWatcher")
            }
        } else {
            // Fresh start - get latest ROWID
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
            log("Fresh start from ROWID: \(lastRowId)", level: .info, component: "MessageWatcher")
        }

        // Set up file system watching
        if enableFileWatcher {
            fileDescriptor = open(watchPath, O_EVTONLY)
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
        } else {
            log("File watching disabled", level: .debug, component: "MessageWatcher")
        }

        // Do an immediate synchronous check
        log("Doing initial check...", level: .info, component: "MessageWatcher")
        checkForNewMessages()
        log("Initial check complete", level: .info, component: "MessageWatcher")

        // Start a background thread for polling (matching MailWatcher pattern)
        if enablePolling {
            shouldStop = false
            let interval = self.pollInterval
            var heartbeatCounter = 0
            let heartbeatInterval = 60  // Log heartbeat every 60 polls (5 min at 5s interval)

            let thread = Thread { [weak self] in
                log("Poll thread running", level: .info, component: "MessageWatcher")
                while let self = self, !self.shouldStop {
                    Thread.sleep(forTimeInterval: interval)
                    if self.shouldStop { break }

                    // Periodic heartbeat to confirm thread is alive
                    heartbeatCounter += 1
                    if heartbeatCounter >= heartbeatInterval {
                        log("Poll thread heartbeat: still running", level: .debug, component: "MessageWatcher")
                        heartbeatCounter = 0
                    }

                    // autoreleasepool to manage memory, checkForNewMessages handles its own errors
                    autoreleasepool {
                        self.checkForNewMessages()
                    }
                }
                log("Poll thread stopped", level: .info, component: "MessageWatcher")
            }
            thread.qualityOfService = .userInitiated
            thread.start()
            watchThread = thread
            log("Poll thread started", level: .info, component: "MessageWatcher")
        } else {
            log("Polling disabled", level: .debug, component: "MessageWatcher")
        }
    }

    /// Stops watching
    func stop() {
        // Signal poll thread to stop
        shouldStop = true

        // Cancel file system watcher
        source?.cancel()
        source = nil

        // Cancel poll thread
        watchThread?.cancel()
        watchThread = nil

        // Close file descriptor if still open
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    /// Manual trigger for message checks (used in tests)
    func checkNow() {
        checkForNewMessages()
    }

    /// Checks for new messages since last check
    private func checkForNewMessages() {
        checkLock.lock()

        if isChecking {
            checkLock.unlock()
            return
        }
        isChecking = true

        // Query DB while holding lock - eliminates race window
        let currentLastRowId = lastRowId
        let messages: [Message]
        do {
            messages = try store.fetchNewMessages(since: currentLastRowId)
            consecutiveFailures = 0
        } catch {
            isChecking = false
            checkLock.unlock()
            handleCheckError(error)
            return
        }

        if !messages.isEmpty {
            log("Found \(messages.count) new message(s) since ROWID \(currentLastRowId)", level: .info, component: "MessageWatcher")
        }

        // Collect messages to dispatch (update all state while holding lock)
        var messagesToDispatch: [Message] = []

        for message in messages {
            if recentlyProcessedRowIds.contains(message.rowId) {
                log("Skipping duplicate ROWID \(message.rowId) (already in recent set)", level: .debug, component: "MessageWatcher")
                continue
            }

            if message.rowId > lastRowId {
                recentlyProcessedRowIds.insert(message.rowId)

                if recentlyProcessedRowIds.count > maxRecentRowIds {
                    if let minRowId = recentlyProcessedRowIds.min() {
                        recentlyProcessedRowIds.remove(minRowId)
                    }
                }

                log("New message from \(message.handleId): \(message.text.prefix(50))...", level: .info, component: "MessageWatcher")
                lastRowId = message.rowId
                messagesToDispatch.append(message)
            }
        }

        isChecking = false
        checkLock.unlock()

        // Dispatch callbacks OUTSIDE lock to avoid deadlocks
        for message in messagesToDispatch {
            saveState()
            onNewMessage(message)
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
