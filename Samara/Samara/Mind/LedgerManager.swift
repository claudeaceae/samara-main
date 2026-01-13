import Foundation

/// Manages session ledgers for structured handoffs
/// Enables context preservation across session boundaries
final class LedgerManager {

    // MARK: - Types

    /// A session ledger containing state to carry forward
    struct Ledger: Codable {
        var sessionId: String
        var chatId: String
        var startedAt: Date
        var lastUpdated: Date
        var activeGoals: [Goal]
        var decisions: [Decision]
        var filesModified: [FileChange]
        var nextSteps: [String]
        var openQuestions: [String]
        var contextPercentage: Double
        var summary: String?

        struct Goal: Codable {
            let description: String
            let status: GoalStatus
            let progress: String?
        }

        enum GoalStatus: String, Codable {
            case pending = "pending"
            case inProgress = "in_progress"
            case completed = "completed"
            case blocked = "blocked"
        }

        struct Decision: Codable {
            let description: String
            let rationale: String
            let timestamp: Date
        }

        struct FileChange: Codable {
            let path: String
            let action: FileAction
            let summary: String
        }

        enum FileAction: String, Codable {
            case created = "created"
            case modified = "modified"
            case deleted = "deleted"
        }

        /// Generate a human-readable summary
        func humanReadable() -> String {
            var lines: [String] = []

            lines.append("# Session Ledger")
            lines.append("Session: \(sessionId)")
            lines.append("Chat: \(chatId)")
            lines.append("Started: \(formatDate(startedAt))")
            lines.append("Last Updated: \(formatDate(lastUpdated))")
            lines.append("Context Usage: \(Int(contextPercentage * 100))%")

            if let summary = summary {
                lines.append("\n## Summary\n\(summary)")
            }

            if !activeGoals.isEmpty {
                lines.append("\n## Active Goals")
                for goal in activeGoals {
                    let status = goal.status == .completed ? "✅" : (goal.status == .inProgress ? "🔄" : "⏳")
                    var line = "- \(status) \(goal.description)"
                    if let progress = goal.progress {
                        line += " (\(progress))"
                    }
                    lines.append(line)
                }
            }

            if !decisions.isEmpty {
                lines.append("\n## Key Decisions")
                for decision in decisions {
                    lines.append("- **\(decision.description)**: \(decision.rationale)")
                }
            }

            if !filesModified.isEmpty {
                lines.append("\n## Files Changed")
                for file in filesModified {
                    lines.append("- [\(file.action.rawValue)] \(file.path): \(file.summary)")
                }
            }

            if !nextSteps.isEmpty {
                lines.append("\n## Next Steps")
                for step in nextSteps {
                    lines.append("- \(step)")
                }
            }

            if !openQuestions.isEmpty {
                lines.append("\n## Open Questions")
                for question in openQuestions {
                    lines.append("- \(question)")
                }
            }

            return lines.joined(separator: "\n")
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        }
    }

    /// Handoff document for session transitions
    struct Handoff: Codable {
        let ledger: Ledger
        let reason: HandoffReason
        let createdAt: Date
        let previousSessionId: String?

        enum HandoffReason: String, Codable {
            case contextThreshold = "context_threshold"
            case sessionTimeout = "session_timeout"
            case userRequested = "user_requested"
            case taskComplete = "task_complete"
            case error = "error"
        }
    }

    // MARK: - Properties

    private let ledgersDir: String
    private let handoffsDir: String

    /// Currently active ledgers by chat ID
    private var activeLedgers: [String: Ledger] = [:]

    /// Lock for thread safety
    private let lock = NSLock()

    // MARK: - Initialization

    init(baseDir: String? = nil) {
        let defaultBase = MindPaths.mindPath("state")

        let base = baseDir ?? defaultBase
        self.ledgersDir = (base as NSString).appendingPathComponent("ledgers")
        self.handoffsDir = (base as NSString).appendingPathComponent("handoffs")

        // Ensure directories exist
        try? FileManager.default.createDirectory(atPath: ledgersDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: handoffsDir, withIntermediateDirectories: true)

        // Load existing ledgers
        loadActiveLedgers()
    }

    // MARK: - Ledger Operations

    /// Get or create a ledger for a chat
    func getLedger(forChat chatId: String, sessionId: String) -> Ledger {
        lock.lock()
        defer { lock.unlock() }

        if let existing = activeLedgers[chatId] {
            return existing
        }

        // Try loading from disk
        if let loaded = loadLedger(forChat: chatId) {
            activeLedgers[chatId] = loaded
            return loaded
        }

        // Create new ledger
        let ledger = Ledger(
            sessionId: sessionId,
            chatId: chatId,
            startedAt: Date(),
            lastUpdated: Date(),
            activeGoals: [],
            decisions: [],
            filesModified: [],
            nextSteps: [],
            openQuestions: [],
            contextPercentage: 0.0,
            summary: nil
        )

        activeLedgers[chatId] = ledger
        saveLedger(ledger)

        return ledger
    }

    /// Update a ledger
    func updateLedger(_ ledger: Ledger) {
        lock.lock()
        defer { lock.unlock() }

        var updated = ledger
        updated.lastUpdated = Date()
        activeLedgers[ledger.chatId] = updated
        saveLedger(updated)
    }

    /// Add a goal to a ledger
    func addGoal(chatId: String, description: String, status: Ledger.GoalStatus = .pending, progress: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        let goal = Ledger.Goal(description: description, status: status, progress: progress)
        ledger.activeGoals.append(goal)
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Update goal status
    func updateGoalStatus(chatId: String, goalIndex: Int, status: Ledger.GoalStatus, progress: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId], goalIndex < ledger.activeGoals.count else { return }

        let oldGoal = ledger.activeGoals[goalIndex]
        ledger.activeGoals[goalIndex] = Ledger.Goal(
            description: oldGoal.description,
            status: status,
            progress: progress ?? oldGoal.progress
        )
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Record a decision
    func recordDecision(chatId: String, description: String, rationale: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        let decision = Ledger.Decision(
            description: description,
            rationale: rationale,
            timestamp: Date()
        )
        ledger.decisions.append(decision)
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Record a file change
    func recordFileChange(chatId: String, path: String, action: Ledger.FileAction, summary: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        let change = Ledger.FileChange(path: path, action: action, summary: summary)
        ledger.filesModified.append(change)
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Add next steps
    func addNextSteps(chatId: String, steps: [String]) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        ledger.nextSteps.append(contentsOf: steps)
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Add open questions
    func addOpenQuestions(chatId: String, questions: [String]) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        ledger.openQuestions.append(contentsOf: questions)
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Update context percentage
    func updateContextPercentage(chatId: String, percentage: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        ledger.contextPercentage = percentage
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    /// Set summary
    func setSummary(chatId: String, summary: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var ledger = activeLedgers[chatId] else { return }

        ledger.summary = summary
        ledger.lastUpdated = Date()

        activeLedgers[chatId] = ledger
        saveLedger(ledger)
    }

    // MARK: - Handoff Operations

    /// Create a handoff document from current ledger
    func createHandoff(forChat chatId: String, reason: Handoff.HandoffReason) -> Handoff? {
        lock.lock()
        defer { lock.unlock() }

        guard let ledger = activeLedgers[chatId] else { return nil }

        let handoff = Handoff(
            ledger: ledger,
            reason: reason,
            createdAt: Date(),
            previousSessionId: ledger.sessionId
        )

        // Save handoff to archive
        saveHandoff(handoff)

        // Clear the active ledger for fresh start
        activeLedgers.removeValue(forKey: chatId)
        deleteLedger(forChat: chatId)

        log("Created handoff for chat \(chatId): \(reason.rawValue)", level: .info, component: "LedgerManager")

        return handoff
    }

    /// Get the most recent handoff for a chat
    func getMostRecentHandoff(forChat chatId: String) -> Handoff? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: handoffsDir)) ?? []

        let chatFiles = files.filter { $0.contains(sanitizeFilename(chatId)) }
            .sorted()
            .reversed()

        guard let mostRecent = chatFiles.first else { return nil }

        let path = (handoffsDir as NSString).appendingPathComponent(mostRecent)
        return loadHandoff(from: path)
    }

    /// Generate context injection from handoff for session continuation
    func contextFromHandoff(_ handoff: Handoff) -> String {
        var lines: [String] = []

        lines.append("## Session Continuity")
        lines.append("This is a continuation from a previous session that ended due to: \(handoff.reason.rawValue)")
        lines.append("")

        lines.append(handoff.ledger.humanReadable())

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func ledgerPath(forChat chatId: String) -> String {
        let filename = sanitizeFilename(chatId) + ".json"
        return (ledgersDir as NSString).appendingPathComponent(filename)
    }

    private func saveLedger(_ ledger: Ledger) {
        let path = ledgerPath(forChat: ledger.chatId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(ledger)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            log("Failed to save ledger for \(ledger.chatId): \(error)", level: .error, component: "LedgerManager")
        }
    }

    private func loadLedger(forChat chatId: String) -> Ledger? {
        let path = ledgerPath(forChat: chatId)

        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try decoder.decode(Ledger.self, from: data)
        } catch {
            log("Failed to load ledger for \(chatId): \(error)", level: .warn, component: "LedgerManager")
            return nil
        }
    }

    private func deleteLedger(forChat chatId: String) {
        let path = ledgerPath(forChat: chatId)
        try? FileManager.default.removeItem(atPath: path)
    }

    private func loadActiveLedgers() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: ledgersDir) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.hasSuffix(".json") {
            let path = (ledgersDir as NSString).appendingPathComponent(file)
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let ledger = try decoder.decode(Ledger.self, from: data)
                activeLedgers[ledger.chatId] = ledger
            } catch {
                log("Failed to load ledger from \(file): \(error)", level: .warn, component: "LedgerManager")
            }
        }

        log("Loaded \(activeLedgers.count) active ledgers", level: .info, component: "LedgerManager")
    }

    private func saveHandoff(_ handoff: Handoff) {
        let timestamp = ISO8601DateFormatter().string(from: handoff.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(timestamp)-\(sanitizeFilename(handoff.ledger.chatId)).json"
        let path = (handoffsDir as NSString).appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(handoff)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            log("Failed to save handoff: \(error)", level: .error, component: "LedgerManager")
        }
    }

    private func loadHandoff(from path: String) -> Handoff? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try decoder.decode(Handoff.self, from: data)
        } catch {
            log("Failed to load handoff from \(path): \(error)", level: .warn, component: "LedgerManager")
            return nil
        }
    }

    private func sanitizeFilename(_ chatId: String) -> String {
        chatId.replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
