import Foundation

// Use the global log function from main.swift
// (declared there as: func log(_ message: String))

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

    init(store: MessageStore, onNewMessage: @escaping (Message) -> Void) {
        self.store = store
        self.onNewMessage = onNewMessage
    }

    /// Starts watching for new messages
    func start() throws {
        // Get the starting point (latest message ID)
        lastRowId = try store.getLatestRowId()
        log("[MessageWatcher] Starting from ROWID: \(lastRowId)")

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

        log("[MessageWatcher] Watching for new messages...")

        // Do an immediate synchronous check
        log("[MessageWatcher] Doing initial check...")
        checkForNewMessages()
        log("[MessageWatcher] Initial check complete")

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
        log("[MessageWatcher] Poll thread started")
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

            if !messages.isEmpty {
                log("[MessageWatcher] Found \(messages.count) new message(s) since ROWID \(currentLastRowId)")
            }

            checkLock.lock()
            for message in messages {
                // Only process if we haven't already moved past this message
                if message.rowId > lastRowId {
                    log("[MessageWatcher] New message from \(message.handleId): \(message.text.prefix(50))...")
                    lastRowId = message.rowId
                    checkLock.unlock()
                    onNewMessage(message)
                    checkLock.lock()
                }
            }
            isChecking = false
            checkLock.unlock()
        } catch {
            log("[MessageWatcher] Error checking messages: \(error)")
            checkLock.lock()
            isChecking = false
            checkLock.unlock()
        }
    }
}

enum MessageWatcherError: Error {
    case cannotOpenFile
}
