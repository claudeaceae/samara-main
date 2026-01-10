import Foundation

/// Manages a queue of proactive messages with pacing to avoid overwhelming
/// Based on Memory Engine concept: proactive initiation with appropriate spacing
final class ProactiveQueue {

    // MARK: - Types

    /// A queued proactive message
    struct QueuedMessage: Codable, Identifiable {
        let id: String
        let content: String
        let priority: Priority
        let source: Source
        let createdAt: Date
        var scheduledFor: Date?
        var sentAt: Date?
        var expiresAt: Date?
        var metadata: [String: String]

        enum Priority: String, Codable, Comparable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case timeSensitive = "time_sensitive"

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                let order: [Priority] = [.low, .medium, .high, .timeSensitive]
                return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
            }
        }

        enum Source: String, Codable {
            case trigger = "trigger"           // From ContextTriggers
            case thought = "thought"           // From Claude's reflection
            case reminder = "reminder"         // Scheduled reminder
            case observation = "observation"   // Noticed something interesting
            case followUp = "follow_up"        // Following up on previous topic
        }

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() > expiresAt
        }

        var isReady: Bool {
            guard let scheduledFor = scheduledFor else { return true }
            return Date() >= scheduledFor
        }
    }

    /// Configuration for message pacing
    struct PacingConfig: Codable {
        var minIntervalSeconds: TimeInterval = 3600     // 1 hour minimum between messages
        var maxMessagesPerDay: Int = 5                  // Max proactive messages per day
        var quietHoursStart: Int = 22                   // 10 PM
        var quietHoursEnd: Int = 8                      // 8 AM
        var batchWindow: TimeInterval = 300             // 5 minutes to batch related messages
        var priorityBoostMultiplier: Double = 0.5       // High priority reduces wait time

        /// Check if current time is in quiet hours
        func isQuietHours(at date: Date = Date()) -> Bool {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)

            if quietHoursStart < quietHoursEnd {
                return hour >= quietHoursStart || hour < quietHoursEnd
            } else {
                return hour >= quietHoursStart || hour < quietHoursEnd
            }
        }
    }

    /// Daily statistics
    struct DailyStats: Codable {
        var date: String  // YYYY-MM-DD
        var messagesSent: Int
        var messagesQueued: Int
        var messagesExpired: Int
        var messagesDropped: Int  // Exceeded daily limit
    }

    // MARK: - Properties

    /// Directory for queue storage
    private let queueDir: String

    /// Pending messages
    private var queue: [QueuedMessage] = []

    /// Pacing configuration
    private(set) var config: PacingConfig

    /// Last message sent time
    private var lastMessageSent: Date?

    /// Daily statistics
    private var todayStats: DailyStats

    /// Lock for thread safety
    private let lock = NSLock()

    // MARK: - Initialization

    init(baseDir: String? = nil) {
        let defaultBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind/state")
            .path

        let base = baseDir ?? defaultBase
        self.queueDir = (base as NSString).appendingPathComponent("proactive-queue")

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: queueDir, withIntermediateDirectories: true)

        // Load config with defaults
        self.config = PacingConfig()
        self.todayStats = DailyStats(
            date: Self.todayString(),
            messagesSent: 0,
            messagesQueued: 0,
            messagesExpired: 0,
            messagesDropped: 0
        )

        // Load state
        loadConfig()
        loadQueue()
        loadStats()

        // Clean expired messages
        cleanExpired()
    }

    // MARK: - Queue Operations

    /// Add a message to the queue
    /// - Returns: The queued message ID, or nil if message was dropped
    @discardableResult
    func enqueue(
        content: String,
        priority: QueuedMessage.Priority = .medium,
        source: QueuedMessage.Source = .thought,
        scheduledFor: Date? = nil,
        expiresIn: TimeInterval? = nil,
        metadata: [String: String] = [:]
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }

        // Check daily limit (time-sensitive bypasses)
        if priority != .timeSensitive && todayStats.messagesSent >= config.maxMessagesPerDay {
            todayStats.messagesDropped += 1
            saveStats()
            log("Dropped proactive message (daily limit reached): \(content.prefix(50))...",
                level: .info, component: "ProactiveQueue")
            return nil
        }

        let message = QueuedMessage(
            id: UUID().uuidString,
            content: content,
            priority: priority,
            source: source,
            createdAt: Date(),
            scheduledFor: scheduledFor,
            sentAt: nil,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            metadata: metadata
        )

        queue.append(message)
        todayStats.messagesQueued += 1
        sortQueue()
        saveQueue()
        saveStats()

        log("Enqueued proactive message [\(priority.rawValue)]: \(content.prefix(50))...",
            level: .info, component: "ProactiveQueue")

        return message.id
    }

    /// Get the next message ready to send (respects pacing)
    /// Returns nil if no message is ready or pacing constraints not met
    func dequeue() -> QueuedMessage? {
        lock.lock()
        defer { lock.unlock() }

        cleanExpired()

        // Check quiet hours
        if config.isQuietHours() {
            // Only time-sensitive messages during quiet hours
            if let index = queue.firstIndex(where: { $0.priority == .timeSensitive && $0.isReady && !$0.isExpired }) {
                return removeAndReturn(at: index)
            }
            return nil
        }

        // Check pacing interval
        if let lastSent = lastMessageSent {
            let elapsed = Date().timeIntervalSince(lastSent)
            let requiredInterval = effectiveInterval(for: queue.first?.priority ?? .medium)
            if elapsed < requiredInterval {
                return nil
            }
        }

        // Find first ready, non-expired message
        guard let index = queue.firstIndex(where: { $0.isReady && !$0.isExpired }) else {
            return nil
        }

        return removeAndReturn(at: index)
    }

    /// Peek at the next message without removing it
    func peek() -> QueuedMessage? {
        lock.lock()
        defer { lock.unlock() }
        return queue.first { $0.isReady && !$0.isExpired }
    }

    /// Mark a message as sent
    func markSent(messageId: String) {
        lock.lock()
        defer { lock.unlock() }

        lastMessageSent = Date()
        todayStats.messagesSent += 1
        saveStats()

        log("Proactive message sent. Daily count: \(todayStats.messagesSent)/\(config.maxMessagesPerDay)",
            level: .info, component: "ProactiveQueue")
    }

    /// Cancel a queued message
    func cancel(messageId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let index = queue.firstIndex(where: { $0.id == messageId }) {
            queue.remove(at: index)
            saveQueue()
            return true
        }
        return false
    }

    /// Get all pending messages
    func getPending() -> [QueuedMessage] {
        lock.lock()
        defer { lock.unlock() }
        return queue.filter { !$0.isExpired }
    }

    /// Get queue status
    func getStatus() -> (pending: Int, sentToday: Int, remainingToday: Int, nextReady: Date?) {
        lock.lock()
        defer { lock.unlock() }

        let pending = queue.filter { !$0.isExpired }.count
        let sentToday = todayStats.messagesSent
        let remainingToday = max(0, config.maxMessagesPerDay - sentToday)

        var nextReady: Date? = nil
        if let lastSent = lastMessageSent, let nextMessage = queue.first(where: { !$0.isExpired }) {
            let interval = effectiveInterval(for: nextMessage.priority)
            let eligibleAt = lastSent.addingTimeInterval(interval)
            if eligibleAt > Date() {
                nextReady = eligibleAt
            }
        }

        return (pending, sentToday, remainingToday, nextReady)
    }

    // MARK: - Configuration

    /// Update pacing configuration
    func updateConfig(_ newConfig: PacingConfig) {
        lock.lock()
        defer { lock.unlock() }

        config = newConfig
        saveConfig()
    }

    // MARK: - Private Helpers

    private func removeAndReturn(at index: Int) -> QueuedMessage {
        var message = queue.remove(at: index)
        message.sentAt = Date()
        saveQueue()
        return message
    }

    private func sortQueue() {
        // Sort by priority (highest first), then by scheduled time, then by creation time
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if let lhsScheduled = lhs.scheduledFor, let rhsScheduled = rhs.scheduledFor {
                return lhsScheduled < rhsScheduled
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func effectiveInterval(for priority: QueuedMessage.Priority) -> TimeInterval {
        switch priority {
        case .timeSensitive:
            return 0  // No delay
        case .high:
            return config.minIntervalSeconds * config.priorityBoostMultiplier
        case .medium:
            return config.minIntervalSeconds
        case .low:
            return config.minIntervalSeconds * 1.5
        }
    }

    private func cleanExpired() {
        let expiredCount = queue.filter { $0.isExpired }.count
        queue.removeAll { $0.isExpired }

        if expiredCount > 0 {
            todayStats.messagesExpired += expiredCount
            saveQueue()
            saveStats()
            log("Cleaned \(expiredCount) expired messages from queue", level: .debug, component: "ProactiveQueue")
        }
    }

    // MARK: - Persistence

    private var queuePath: String {
        (queueDir as NSString).appendingPathComponent("queue.json")
    }

    private var configPath: String {
        (queueDir as NSString).appendingPathComponent("config.json")
    }

    private var statsPath: String {
        (queueDir as NSString).appendingPathComponent("stats.json")
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queuePath) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: queuePath))
            queue = try decoder.decode([QueuedMessage].self, from: data)
            log("Loaded \(queue.count) queued messages", level: .info, component: "ProactiveQueue")
        } catch {
            log("Failed to load queue: \(error)", level: .warn, component: "ProactiveQueue")
        }
    }

    private func saveQueue() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(queue)
            try data.write(to: URL(fileURLWithPath: queuePath), options: .atomic)
        } catch {
            log("Failed to save queue: \(error)", level: .error, component: "ProactiveQueue")
        }
    }

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath) else { return }

        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            config = try decoder.decode(PacingConfig.self, from: data)
        } catch {
            log("Failed to load config: \(error)", level: .warn, component: "ProactiveQueue")
        }
    }

    private func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            log("Failed to save config: \(error)", level: .error, component: "ProactiveQueue")
        }
    }

    private func loadStats() {
        guard FileManager.default.fileExists(atPath: statsPath) else { return }

        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statsPath))
            let loaded = try decoder.decode(DailyStats.self, from: data)

            // Check if stats are for today
            if loaded.date == Self.todayString() {
                todayStats = loaded
            }
            // Otherwise keep fresh stats for today
        } catch {
            log("Failed to load stats: \(error)", level: .warn, component: "ProactiveQueue")
        }
    }

    private func saveStats() {
        // Ensure date is current
        let today = Self.todayString()
        if todayStats.date != today {
            todayStats = DailyStats(
                date: today,
                messagesSent: 0,
                messagesQueued: 0,
                messagesExpired: 0,
                messagesDropped: 0
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(todayStats)
            try data.write(to: URL(fileURLWithPath: statsPath), options: .atomic)
        } catch {
            log("Failed to save stats: \(error)", level: .error, component: "ProactiveQueue")
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
