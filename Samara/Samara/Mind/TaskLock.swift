import Foundation

/// Information about a currently running task
struct TaskInfo: Codable {
    let task: String           // "wake", "dream", "message", "email", "bluesky", "github"
    let started: Date
    let chat: String?          // chatIdentifier if message-related, nil for autonomous tasks
    let pid: Int32             // Process ID for stale lock detection
}

/// Manages a system-wide lock file to coordinate Claude invocations
/// Prevents multiple concurrent Claude processes from running
final class TaskLock {

    static let lockPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/claude.lock"

    /// Attempt to acquire the lock for a given task
    /// - Parameters:
    ///   - task: Description of the task (e.g., "wake", "message", "email")
    ///   - chat: Optional chat identifier if this is a message-related task
    /// - Returns: true if lock was acquired, false if another task is running
    static func acquire(task: String, chat: String? = nil) -> Bool {
        // First check if there's a stale lock we should clean up
        if isStale() {
            print("[TaskLock] Releasing stale lock")
            release()
        }

        // Check if already locked
        if isLocked() {
            print("[TaskLock] Already locked by another task")
            return false
        }

        // Create lock atomically
        let info = TaskInfo(
            task: task,
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
            let tempPath = lockPath + ".tmp"
            try data.write(to: URL(fileURLWithPath: tempPath))
            try FileManager.default.moveItem(atPath: tempPath, toPath: lockPath)

            print("[TaskLock] Acquired lock for task: \(task)")
            return true
        } catch {
            print("[TaskLock] Failed to acquire lock: \(error)")
            return false
        }
    }

    /// Release the lock
    static func release() {
        do {
            try FileManager.default.removeItem(atPath: lockPath)
            print("[TaskLock] Released lock")
        } catch {
            // File might not exist, that's fine
            if (error as NSError).code != NSFileNoSuchFileError {
                print("[TaskLock] Failed to release lock: \(error)")
            }
        }
    }

    /// Get information about the current task holding the lock
    /// - Returns: TaskInfo if locked, nil if not locked
    static func currentTask() -> TaskInfo? {
        guard FileManager.default.fileExists(atPath: lockPath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: lockPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TaskInfo.self, from: data)
        } catch {
            print("[TaskLock] Failed to read lock info: \(error)")
            return nil
        }
    }

    /// Check if the lock is currently held
    static func isLocked() -> Bool {
        return FileManager.default.fileExists(atPath: lockPath)
    }

    /// Check if the lock is stale (process that created it is no longer running)
    static func isStale() -> Bool {
        guard let info = currentTask() else {
            return false
        }

        // Check if the PID is still running
        let result = kill(info.pid, 0)  // Signal 0 just checks if process exists
        if result == -1 && errno == ESRCH {
            // ESRCH means no such process
            print("[TaskLock] Lock is stale - PID \(info.pid) no longer running")
            return true
        }

        // Also consider a lock stale if it's been held for more than 30 minutes
        // (normal Claude invocations shouldn't take this long)
        let staleDuration: TimeInterval = 30 * 60  // 30 minutes
        if Date().timeIntervalSince(info.started) > staleDuration {
            print("[TaskLock] Lock is stale - held for more than 30 minutes")
            return true
        }

        return false
    }

    /// Get a human-friendly description of the current task
    /// - Returns: Description string like "wake cycle" or "another conversation"
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
