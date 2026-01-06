import Foundation

/// Scope of a task lock - determines what blocks what
enum LockScope: Codable, Equatable, Hashable {
    case conversation(chatIdentifier: String)  // Per-chat lock for message handling
    case backgroundTask(type: String)          // Webcam, web fetch, skills
    case systemTask(name: String)              // Wake cycle, dream cycle

    var filename: String {
        switch self {
        case .conversation(let chatId):
            // Sanitize chatIdentifier for filesystem (replace unsafe chars)
            let sanitized = chatId.replacingOccurrences(of: "+", with: "_")
                .replacingOccurrences(of: "@", with: "_")
                .replacingOccurrences(of: ".", with: "_")
            return "chat-\(sanitized).lock"
        case .backgroundTask(let type):
            return "task-\(type).lock"
        case .systemTask(let name):
            return "system-\(name).lock"
        }
    }

    var description: String {
        switch self {
        case .conversation(let chatId):
            return "conversation (\(chatId.prefix(12))...)"
        case .backgroundTask(let type):
            return "\(type) task"
        case .systemTask(let name):
            return "\(name) cycle"
        }
    }
}

/// Information about a currently running task
struct TaskInfo: Codable {
    let task: String           // "wake", "dream", "message", "webcam", etc.
    let scope: LockScope       // The scope of this lock
    let started: Date
    let chat: String?          // chatIdentifier if message-related, nil for autonomous tasks
    let pid: Int32             // Process ID for stale lock detection
}

/// Manages scoped lock files to coordinate Claude invocations
/// Allows concurrent conversations across different chats while serializing within each chat
final class TaskLock {

    /// Base directory for all lock files
    static let locksDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/locks"

    /// Legacy single lock path for backward compatibility
    static let legacyLockPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/claude.lock"

    /// Initialize locks directory
    static func ensureLocksDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: locksDir) {
            do {
                try fm.createDirectory(atPath: locksDir, withIntermediateDirectories: true)
                log("Created locks directory", level: .info, component: "TaskLock")
            } catch {
                log("Failed to create locks directory: \(error)", level: .error, component: "TaskLock")
            }
        }

        // Clean up legacy single lock if it exists
        if fm.fileExists(atPath: legacyLockPath) {
            try? fm.removeItem(atPath: legacyLockPath)
            log("Removed legacy single lock file", level: .info, component: "TaskLock")
        }
    }

    /// Get path for a specific scope's lock file
    static func lockPath(for scope: LockScope) -> String {
        ensureLocksDirectory()
        return "\(locksDir)/\(scope.filename)"
    }

    // MARK: - Scoped Lock Operations

    /// Attempt to acquire the lock for a given scope
    /// - Parameters:
    ///   - scope: The scope to lock
    ///   - task: Description of the task (e.g., "message", "webcam")
    /// - Returns: true if lock was acquired, false if already locked
    static func acquire(scope: LockScope, task: String) -> Bool {
        let path = lockPath(for: scope)

        // First check if there's a stale lock we should clean up
        if isStale(scope: scope) {
            log("Releasing stale lock for \(scope.description)", level: .warn, component: "TaskLock")
            release(scope: scope)
        }

        // Check if already locked
        if isLocked(scope: scope) {
            log("Already locked: \(scope.description)", level: .debug, component: "TaskLock")
            return false
        }

        // Determine chat from scope
        let chat: String?
        if case .conversation(let chatId) = scope {
            chat = chatId
        } else {
            chat = nil
        }

        // Create lock atomically
        let info = TaskInfo(
            task: task,
            scope: scope,
            started: Date(),
            chat: chat,
            pid: ProcessInfo.processInfo.processIdentifier
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(info)

            // Write to temp file first, then rename (atomic)
            let tempPath = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tempPath))
            try FileManager.default.moveItem(atPath: tempPath, toPath: path)

            log("Acquired lock for \(scope.description)", level: .info, component: "TaskLock")
            return true
        } catch {
            log("Failed to acquire lock: \(error)", level: .error, component: "TaskLock")
            return false
        }
    }

    /// Release the lock for a specific scope
    static func release(scope: LockScope) {
        let path = lockPath(for: scope)
        do {
            try FileManager.default.removeItem(atPath: path)
            log("Released lock for \(scope.description)", level: .debug, component: "TaskLock")
        } catch {
            // File might not exist, that's fine
            if (error as NSError).code != NSFileNoSuchFileError {
                log("Failed to release lock: \(error)", level: .warn, component: "TaskLock")
            }
        }
    }

    /// Get information about the task holding a specific scope's lock
    static func currentTask(scope: LockScope) -> TaskInfo? {
        let path = lockPath(for: scope)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TaskInfo.self, from: data)
        } catch {
            log("Failed to read lock info: \(error)", level: .warn, component: "TaskLock")
            return nil
        }
    }

    /// Check if a specific scope is currently locked
    static func isLocked(scope: LockScope) -> Bool {
        let path = lockPath(for: scope)
        return FileManager.default.fileExists(atPath: path)
    }

    /// Check if a specific scope's lock is stale
    static func isStale(scope: LockScope) -> Bool {
        guard let info = currentTask(scope: scope) else {
            return false
        }

        // Check if the PID is still running
        let result = kill(info.pid, 0)  // Signal 0 just checks if process exists
        if result == -1 && errno == ESRCH {
            log("Lock is stale - PID \(info.pid) no longer running", level: .warn, component: "TaskLock")
            return true
        }

        // Also consider a lock stale if it's been held for more than 30 minutes
        let staleDuration: TimeInterval = 30 * 60  // 30 minutes
        if Date().timeIntervalSince(info.started) > staleDuration {
            log("Lock is stale - held for more than 30 minutes", level: .warn, component: "TaskLock")
            return true
        }

        return false
    }

    // MARK: - Convenience Methods (for backward compatibility and common patterns)

    /// Legacy: acquire with task name and optional chat (creates appropriate scope)
    @available(*, deprecated, message: "Use acquire(scope:task:) instead")
    static func acquire(task: String, chat: String? = nil) -> Bool {
        let scope: LockScope
        if let chatId = chat {
            scope = .conversation(chatIdentifier: chatId)
        } else {
            scope = .systemTask(name: task)
        }
        return acquire(scope: scope, task: task)
    }

    /// Legacy: release without scope (releases ALL locks - use with caution)
    @available(*, deprecated, message: "Use release(scope:) instead")
    static func release() {
        // Release all lock files
        let fm = FileManager.default
        ensureLocksDirectory()

        do {
            let files = try fm.contentsOfDirectory(atPath: locksDir)
            for file in files where file.hasSuffix(".lock") {
                let path = "\(locksDir)/\(file)"
                try? fm.removeItem(atPath: path)
            }
            log("Released all locks", level: .debug, component: "TaskLock")
        } catch {
            log("Failed to enumerate locks: \(error)", level: .warn, component: "TaskLock")
        }
    }

    /// Check if ANY lock is currently held (for backward compatibility)
    static func isLocked() -> Bool {
        return anyLocked()
    }

    /// Check if any lock is currently held
    static func anyLocked() -> Bool {
        let fm = FileManager.default
        ensureLocksDirectory()

        do {
            let files = try fm.contentsOfDirectory(atPath: locksDir)
            return files.contains { $0.hasSuffix(".lock") }
        } catch {
            return false
        }
    }

    /// Check if any lock is stale and needs cleanup
    static func isStale() -> Bool {
        let fm = FileManager.default
        ensureLocksDirectory()

        do {
            let files = try fm.contentsOfDirectory(atPath: locksDir)
            for file in files where file.hasSuffix(".lock") {
                let path = "\(locksDir)/\(file)"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let info = try? JSONDecoder().decode(TaskInfo.self, from: data) {
                    // Check if PID is still running
                    let result = kill(info.pid, 0)
                    if result == -1 && errno == ESRCH {
                        return true
                    }
                    // Check for timeout
                    if Date().timeIntervalSince(info.started) > 30 * 60 {
                        return true
                    }
                }
            }
        } catch {
            // Ignore errors
        }
        return false
    }

    /// Clean up all stale locks
    static func cleanupStaleLocks() {
        let fm = FileManager.default
        ensureLocksDirectory()

        do {
            let files = try fm.contentsOfDirectory(atPath: locksDir)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for file in files where file.hasSuffix(".lock") {
                let path = "\(locksDir)/\(file)"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let info = try? decoder.decode(TaskInfo.self, from: data) {
                    // Check if stale
                    let result = kill(info.pid, 0)
                    let isStale = (result == -1 && errno == ESRCH) ||
                                  Date().timeIntervalSince(info.started) > 30 * 60

                    if isStale {
                        try? fm.removeItem(atPath: path)
                        log("Cleaned up stale lock: \(file)", level: .info, component: "TaskLock")
                    }
                }
            }
        } catch {
            log("Failed to cleanup stale locks: \(error)", level: .warn, component: "TaskLock")
        }
    }

    /// Get all currently active locks
    static func activeLocks() -> [TaskInfo] {
        var locks: [TaskInfo] = []
        let fm = FileManager.default
        ensureLocksDirectory()

        do {
            let files = try fm.contentsOfDirectory(atPath: locksDir)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for file in files where file.hasSuffix(".lock") {
                let path = "\(locksDir)/\(file)"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let info = try? decoder.decode(TaskInfo.self, from: data) {
                    locks.append(info)
                }
            }
        } catch {
            // Ignore
        }
        return locks
    }

    /// Get current task info (for backward compatibility - returns first lock found)
    static func currentTask() -> TaskInfo? {
        return activeLocks().first
    }

    /// Get a human-friendly description of the current task
    static func taskDescription() -> String {
        guard let info = currentTask() else {
            return "something"
        }

        switch info.task {
        case "wake":
            return "a wake cycle"
        case "dream":
            return "a dream cycle"
        case "message":
            return "another conversation"
        case "webcam":
            return "a webcam capture"
        case "email":
            return "an email"
        case "bluesky":
            return "Bluesky stuff"
        case "github":
            return "GitHub notifications"
        default:
            return info.task
        }
    }
}
