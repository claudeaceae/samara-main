import Foundation

/// Monitors task locks and processes queued messages when chat-specific locks are released
/// With per-chat locking, we can process each chat's queue independently
final class QueueProcessor {

    /// Polling interval for checking the lock status
    private let pollInterval: TimeInterval = 5.0

    /// Reference to the session manager for reinjecting messages
    private weak var sessionManager: SessionManager?

    /// Background thread for monitoring
    private var monitorThread: Thread?

    /// Flag to stop monitoring
    private var shouldStop = false

    init() {}

    /// Set the session manager to use for reinjecting messages
    func setSessionManager(_ manager: SessionManager) {
        self.sessionManager = manager
    }

    /// Start monitoring the queue
    func startMonitoring() {
        guard monitorThread == nil else {
            log("Already monitoring", level: .debug, component: "QueueProcessor")
            return
        }

        shouldStop = false
        monitorThread = Thread { [weak self] in
            self?.monitorLoop()
        }
        monitorThread?.name = "QueueProcessor"
        monitorThread?.start()
        log("Started monitoring", level: .info, component: "QueueProcessor")
    }

    /// Stop monitoring the queue
    func stopMonitoring() {
        shouldStop = true
        monitorThread = nil
        log("Stopped monitoring", level: .info, component: "QueueProcessor")
    }

    /// Main monitoring loop
    private func monitorLoop() {
        while !shouldStop {
            Thread.sleep(forTimeInterval: pollInterval)

            // Check for stale locks and clean them up
            TaskLock.cleanupStaleLocks()

            // Check each chat's queue independently
            if !MessageQueue.isEmpty() {
                processQueuePerChat()
            }
        }
    }

    /// Process queued messages per-chat, only processing chats whose locks are free
    private func processQueuePerChat() {
        guard let sessionManager = sessionManager else {
            log("No session manager set, cannot process queue", level: .error, component: "QueueProcessor")
            return
        }

        // Get all chats that have queued messages
        let queuedChats = MessageQueue.queuedChats()
        if queuedChats.isEmpty { return }

        log("Checking \(queuedChats.count) chat(s) with queued messages", level: .debug, component: "QueueProcessor")

        for chatId in queuedChats {
            let scope = LockScope.conversation(chatIdentifier: chatId)

            // Only process if THIS chat's lock is free
            if !TaskLock.isLocked(scope: scope) {
                log("Chat \(chatId.prefix(12))... is unlocked, processing queued messages", level: .info, component: "QueueProcessor")
                processQueueForChat(chatId, sessionManager: sessionManager)
            } else {
                log("Chat \(chatId.prefix(12))... still locked, skipping", level: .debug, component: "QueueProcessor")
            }
        }
    }

    /// Process queued messages for a specific chat
    private func processQueueForChat(_ chatIdentifier: String, sessionManager: SessionManager) {
        let queuedMessages = MessageQueue.dequeue(forChat: chatIdentifier)
        if queuedMessages.isEmpty { return }

        log("Reinjecting \(queuedMessages.count) message(s) for chat \(chatIdentifier.prefix(12))...", level: .info, component: "QueueProcessor")

        // Reinject messages into session manager
        // The session manager will handle batching (11-second window)
        for queued in queuedMessages {
            let message = queued.message.toMessage()
            sessionManager.addMessage(message)
        }
    }

    /// Legacy: Process all queued messages (for backward compatibility)
    private func processQueue() {
        guard let sessionManager = sessionManager else {
            log("No session manager set, cannot process queue", level: .error, component: "QueueProcessor")
            return
        }

        let queuedMessages = MessageQueue.dequeueAll()
        if queuedMessages.isEmpty { return }

        log("Processing \(queuedMessages.count) queued message(s)", level: .info, component: "QueueProcessor")

        // Group messages by chat to maintain proper batching
        var messagesByChat: [String: [Message]] = [:]
        for queued in queuedMessages {
            let message = queued.message.toMessage()
            if messagesByChat[message.chatIdentifier] == nil {
                messagesByChat[message.chatIdentifier] = []
            }
            messagesByChat[message.chatIdentifier]!.append(message)
        }

        // Reinject messages into session manager
        // The session manager will handle batching (11-second window)
        for (chatId, messages) in messagesByChat {
            log("Reinjecting \(messages.count) message(s) for chat \(chatId)", level: .info, component: "QueueProcessor")
            for message in messages {
                sessionManager.addMessage(message)
            }
        }
    }
}
