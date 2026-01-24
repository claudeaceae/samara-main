import Foundation

/// Log levels for the Samara logging system
enum LogLevel: String, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.order < rhs.order
    }
}

/// Thread-safe logger with file persistence, log levels, and critical failure alerting
final class Logger {
    static let shared = Logger()

    /// Minimum log level to output (default: .info in release, .debug in debug)
    #if DEBUG
    var minimumLevel: LogLevel = .debug
    #else
    var minimumLevel: LogLevel = .info
    #endif

    /// Path to the log file
    private let logUrl: URL

    /// Path to the mind directory (for alert script)
    private let mindPath: String

    /// Lock for thread-safe file writes
    private let logLock = NSLock()

    /// Date formatter for log rotation
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Maximum log file size before rotation (10 MB)
    private let maxLogSize: UInt64 = 10 * 1024 * 1024

    /// Number of rotated logs to keep
    private let maxRotatedLogs = 7

    private init() {
        mindPath = MindPaths.mindPath()
        let logsDir = MindPaths.mindURL("system/logs")

        // Ensure logs directory exists
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        logUrl = logsDir.appendingPathComponent("samara.log")

        // Rotate logs on startup if needed
        rotateLogsIfNeeded()
    }

    /// Main logging function
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Log level (default: .info)
    ///   - component: Component name for filtering (default: "Main")
    func log(_ message: String, level: LogLevel = .info, component: String = "Main") {
        // Filter by minimum level
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(component)] \(message)\n"

        // Print to stdout
        print("[\(level.rawValue)] [\(component)] \(message)")

        // Write to file
        writeToFile(line)
    }

    /// Logs a critical failure and sends an iMessage alert
    /// - Parameters:
    ///   - message: The error message
    ///   - component: Component where the failure occurred
    func alertCriticalFailure(_ message: String, component: String = "Main") {
        // Log at error level
        log(message, level: .error, component: component)

        // Send iMessage alert
        let alertScript = "\(mindPath)/bin/message"
        guard FileManager.default.fileExists(atPath: alertScript) else {
            log("Alert script not found at \(alertScript)", level: .warn, component: "Logger")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [alertScript, "⚠️ SAMARA ALERT [\(component)]: \(message)"]

        do {
            try process.run()
            // Don't wait - fire and forget
        } catch {
            log("Failed to send alert: \(error)", level: .warn, component: "Logger")
        }
    }

    // MARK: - Private

    private func writeToFile(_ line: String) {
        logLock.lock()
        defer { logLock.unlock() }

        do {
            if FileManager.default.fileExists(atPath: logUrl.path) {
                let handle = try FileHandle(forWritingTo: logUrl)
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try handle.close()
            } else {
                // Create new file
                try line.data(using: .utf8)?.write(to: logUrl)
            }
        } catch {
            // Can't log the error since we're already in the logger
            print("[Logger] Failed to write to log file: \(error)")
        }
    }

    /// Rotates logs if current log exceeds max size
    private func rotateLogsIfNeeded() {
        logLock.lock()
        defer { logLock.unlock() }

        guard FileManager.default.fileExists(atPath: logUrl.path) else { return }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: logUrl.path)
            let size = attrs[.size] as? UInt64 ?? 0

            if size > maxLogSize {
                rotateLogFiles()
            }
        } catch {
            print("[Logger] Failed to check log size: \(error)")
        }
    }

    /// Performs log rotation
    private func rotateLogFiles() {
        let fileManager = FileManager.default
        let logsDir = logUrl.deletingLastPathComponent()
        let baseName = logUrl.deletingPathExtension().lastPathComponent
        let ext = logUrl.pathExtension

        // Delete oldest log if we have too many
        let oldestPath = logsDir.appendingPathComponent("\(baseName).\(maxRotatedLogs).\(ext)").path
        try? fileManager.removeItem(atPath: oldestPath)

        // Shift existing rotated logs
        for i in stride(from: maxRotatedLogs - 1, through: 1, by: -1) {
            let oldPath = logsDir.appendingPathComponent("\(baseName).\(i).\(ext)").path
            let newPath = logsDir.appendingPathComponent("\(baseName).\(i + 1).\(ext)").path
            if fileManager.fileExists(atPath: oldPath) {
                try? fileManager.moveItem(atPath: oldPath, toPath: newPath)
            }
        }

        // Rotate current log to .1
        let rotatedPath = logsDir.appendingPathComponent("\(baseName).1.\(ext)").path
        try? fileManager.moveItem(atPath: logUrl.path, toPath: rotatedPath)

        // Compress rotated log
        compressLogFile(at: rotatedPath)

        print("[Logger] Rotated logs")
    }

    /// Compresses a log file using gzip
    private func compressLogFile(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-f", path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[Logger] Failed to compress log: \(error)")
        }
    }
}

// MARK: - Global convenience functions

/// Logs a message with the specified level and component
/// - Parameters:
///   - message: The message to log
///   - level: Log level (default: .info)
///   - component: Component name (default: "Main")
func log(_ message: String, level: LogLevel = .info, component: String = "Main") {
    Logger.shared.log(message, level: level, component: component)
}

/// Logs a critical failure and sends an iMessage alert
/// - Parameters:
///   - message: The error message
///   - component: Component where the failure occurred
func alertCriticalFailure(_ message: String, component: String = "Main") {
    Logger.shared.alertCriticalFailure(message, component: component)
}
