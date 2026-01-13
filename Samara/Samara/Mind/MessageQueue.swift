import Foundation

/// A serializable version of Message for queue persistence
struct SerializableMessage: Codable {
    let rowId: Int64
    let text: String
    let date: Date
    let isFromMe: Bool
    let handleId: String
    let chatId: Int64
    let isGroupChat: Bool
    let chatIdentifier: String
    let attachmentPaths: [String]  // Just the paths, not full Attachment structs
    let attachmentMimeTypes: [String]
    let attachmentFileNames: [String]
    let attachmentIsSticker: [Bool]
    let reactionTypeRaw: Int?
    let reactedToText: String?

    init(from message: Message) {
        self.rowId = message.rowId
        self.text = message.text
        self.date = message.date
        self.isFromMe = message.isFromMe
        self.handleId = message.handleId
        self.chatId = message.chatId
        self.isGroupChat = message.isGroupChat
        self.chatIdentifier = message.chatIdentifier
        self.attachmentPaths = message.attachments.map { $0.filePath }
        self.attachmentMimeTypes = message.attachments.map { $0.mimeType }
        self.attachmentFileNames = message.attachments.map { $0.fileName }
        self.attachmentIsSticker = message.attachments.map { $0.isSticker }
        self.reactionTypeRaw = message.reactionType?.rawValue
        self.reactedToText = message.reactedToText
    }

    func toMessage() -> Message {
        // Reconstruct attachments
        var attachments: [Attachment] = []
        for i in 0..<attachmentPaths.count {
            attachments.append(Attachment(
                filePath: attachmentPaths[i],
                mimeType: attachmentMimeTypes.indices.contains(i) ? attachmentMimeTypes[i] : "application/octet-stream",
                fileName: attachmentFileNames.indices.contains(i) ? attachmentFileNames[i] : "file",
                isSticker: attachmentIsSticker.indices.contains(i) ? attachmentIsSticker[i] : false
            ))
        }

        return Message(
            rowId: rowId,
            text: text,
            date: date,
            isFromMe: isFromMe,
            handleId: handleId,
            chatId: chatId,
            isGroupChat: isGroupChat,
            chatIdentifier: chatIdentifier,
            attachments: attachments,
            reactionType: reactionTypeRaw.flatMap { ReactionType(rawValue: $0) },
            reactedToText: reactedToText
        )
    }
}

/// A queued message with metadata
struct QueuedMessage: Codable {
    let message: SerializableMessage
    let queuedAt: Date
    let acknowledged: Bool
}

/// Manages a persistent queue of messages waiting to be processed
final class MessageQueue {

    static let queuePath = MindPaths.mindPath("message-queue.json")
    static let maxQueueSize = 50  // Prevent unbounded queue growth

    private static let lock = NSLock()

    /// Enqueue a message for later processing
    /// - Parameters:
    ///   - message: The message to queue
    ///   - acknowledged: Whether an acknowledgment has been sent for this message
    static func enqueue(_ message: Message, acknowledged: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()

        // Check if this message is already queued (by rowId)
        if queue.contains(where: { $0.message.rowId == message.rowId }) {
            log("Message \(message.rowId) already in queue, skipping", level: .debug, component: "MessageQueue")
            return
        }

        let queuedMessage = QueuedMessage(
            message: SerializableMessage(from: message),
            queuedAt: Date(),
            acknowledged: acknowledged
        )

        queue.append(queuedMessage)

        // Limit queue size - drop oldest if necessary
        if queue.count > maxQueueSize {
            let dropped = queue.count - maxQueueSize
            queue = Array(queue.suffix(maxQueueSize))
            log("Queue overflow - dropped \(dropped) oldest message(s)", level: .warn, component: "MessageQueue")
        }

        saveQueue(queue)
        log("Enqueued message \(message.rowId) for chat \(message.chatIdentifier)", level: .debug, component: "MessageQueue")
    }

    /// Dequeue all messages, clearing the queue
    /// - Returns: Array of queued messages, grouped by chat
    static func dequeueAll() -> [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }

        let queue = loadQueue()
        if queue.isEmpty { return [] }

        // Clear the queue
        saveQueue([])
        log("Dequeued \(queue.count) message(s)", level: .info, component: "MessageQueue")

        return queue
    }

    /// Dequeue messages for a specific chat
    /// - Parameter chatIdentifier: The chat to dequeue messages for
    /// - Returns: Array of queued messages for that chat
    static func dequeue(forChat chatIdentifier: String) -> [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }

        var queue = loadQueue()
        let chatMessages = queue.filter { $0.message.chatIdentifier == chatIdentifier }
        queue = queue.filter { $0.message.chatIdentifier != chatIdentifier }

        saveQueue(queue)
        log("Dequeued \(chatMessages.count) message(s) for chat \(chatIdentifier)", level: .info, component: "MessageQueue")

        return chatMessages
    }

    /// Check if the queue is empty
    static func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadQueue().isEmpty
    }

    /// Get the count of messages in the queue
    static func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadQueue().count
    }

    /// Clear all messages from the queue
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        saveQueue([])
        log("Queue cleared", level: .info, component: "MessageQueue")
    }

    /// Get all chats that have queued messages
    static func queuedChats() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(loadQueue().map { $0.message.chatIdentifier })
    }

    // MARK: - Private

    private static func loadQueue() -> [QueuedMessage] {
        guard FileManager.default.fileExists(atPath: queuePath) else {
            return []
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: queuePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([QueuedMessage].self, from: data)
        } catch {
            log("Failed to load queue: \(error)", level: .warn, component: "MessageQueue")
            return []
        }
    }

    private static func saveQueue(_ queue: [QueuedMessage]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(queue)
            try data.write(to: URL(fileURLWithPath: queuePath))
        } catch {
            log("Failed to save queue: \(error)", level: .error, component: "MessageQueue")
        }
    }
}
