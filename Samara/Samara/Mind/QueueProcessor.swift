import Foundation

/// Monitors the task lock and processes queued messages when the lock is released
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
            print("[QueueProcessor] Already monitoring")
            return
        }

        shouldStop = false
        monitorThread = Thread { [weak self] in
            self?.monitorLoop()
        }
        monitorThread?.name = "QueueProcessor"
        monitorThread?.start()
        print("[QueueProcessor] Started monitoring")
    }

    /// Stop monitoring the queue
    func stopMonitoring() {
        shouldStop = true
        monitorThread = nil
        print("[QueueProcessor] Stopped monitoring")
    }

    /// Main monitoring loop
    private func monitorLoop() {
        while !shouldStop {
            Thread.sleep(forTimeInterval: pollInterval)

            // Check for stale locks and clean them up
            if TaskLock.isStale() {
                print("[QueueProcessor] Detected stale lock, releasing...")
                TaskLock.release()
            }

            // If not locked and queue has messages, process them
            if !TaskLock.isLocked() && !MessageQueue.isEmpty() {
                processQueue()
            }
        }
    }

    /// Process all queued messages by reinjecting them into the session manager
    private func processQueue() {
        guard let sessionManager = sessionManager else {
            print("[QueueProcessor] No session manager set, cannot process queue")
            return
        }

        let queuedMessages = MessageQueue.dequeueAll()
        if queuedMessages.isEmpty { return }

        print("[QueueProcessor] Processing \(queuedMessages.count) queued message(s)")

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
            print("[QueueProcessor] Reinjecting \(messages.count) message(s) for chat \(chatId)")
            for message in messages {
                sessionManager.addMessage(message)
            }
        }
    }
}
