import Foundation

/// Logs conversations to daily episode files
final class EpisodeLogger {
    private let episodesPath: String
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    init() {
        let mindPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
            .path
        self.episodesPath = (mindPath as NSString).appendingPathComponent("memory/episodes")

        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        self.timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
    }

    /// Logs a conversation exchange (message + response)
    /// - Parameters:
    ///   - sender: Who sent the message (usually "É")
    ///   - message: The incoming message
    ///   - response: Claude's response
    ///   - source: The source channel (e.g., "iMessage", "Direct", "Autonomous")
    func logExchange(from sender: String, message: String, response: String, source: String = "iMessage") {
        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)

        let episodePath = (episodesPath as NSString).appendingPathComponent("\(dateString).md")

        // Create episode file with header if it doesn't exist
        if !FileManager.default.fileExists(atPath: episodePath) {
            let header = """
                # Episode: \(dateString)

                Daily log of conversations and observations.

                ---

                """
            try? header.write(toFile: episodePath, atomically: true, encoding: .utf8)
        }

        // Format the exchange with source tag
        let entry = """

            ## \(timeString) [\(source)]

            **É:** \(message)

            **Claude:** \(response)

            """

        // Append to episode file
        if let fileHandle = FileHandle(forWritingAtPath: episodePath) {
            fileHandle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        }

        log("Logged exchange to \(dateString).md", level: .debug, component: "EpisodeLogger")
    }

    /// Logs a standalone observation or note
    /// - Parameters:
    ///   - note: The note content
    ///   - source: The source channel (e.g., "Direct", "Autonomous")
    func logNote(_ note: String, source: String = "Note") {
        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)

        let episodePath = (episodesPath as NSString).appendingPathComponent("\(dateString).md")

        // Create episode file with header if it doesn't exist
        if !FileManager.default.fileExists(atPath: episodePath) {
            let header = """
                # Episode: \(dateString)

                Daily log of conversations and observations.

                ---

                """
            try? header.write(toFile: episodePath, atomically: true, encoding: .utf8)
        }

        let entry = """

            ## \(timeString) [\(source)]

            \(note)

            """

        if let fileHandle = FileHandle(forWritingAtPath: episodePath) {
            fileHandle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        }
    }

    /// Logs an outbound message (from Claude to user)
    /// Used by MessageBus to track all outgoing communications
    /// - Parameters:
    ///   - message: The outbound message content
    ///   - source: The source channel type (e.g., "iMessage", "Location", "Wake", "Alert")
    func logOutbound(_ message: String, source: String) {
        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)

        let episodePath = (episodesPath as NSString).appendingPathComponent("\(dateString).md")

        // Create episode file with header if it doesn't exist
        if !FileManager.default.fileExists(atPath: episodePath) {
            let header = """
                # Episode: \(dateString)

                Daily log of conversations and observations.

                ---

                """
            try? header.write(toFile: episodePath, atomically: true, encoding: .utf8)
        }

        let entry = """

            ## \(timeString) [\(source)]

            **Claude:** \(message)

            """

        if let fileHandle = FileHandle(forWritingAtPath: episodePath) {
            fileHandle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        }

        log("Logged outbound [\(source)] to \(dateString).md", level: .debug, component: "EpisodeLogger")
    }

    /// Logs a sense event (from satellite services)
    /// - Parameters:
    ///   - sense: The sense type (e.g., "location", "webhook", "feed")
    ///   - data: The event data as formatted string
    func logSenseEvent(sense: String, data: String) {
        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)

        let episodePath = (episodesPath as NSString).appendingPathComponent("\(dateString).md")

        // Create episode file with header if it doesn't exist
        if !FileManager.default.fileExists(atPath: episodePath) {
            let header = """
                # Episode: \(dateString)

                Daily log of conversations and observations.

                ---

                """
            try? header.write(toFile: episodePath, atomically: true, encoding: .utf8)
        }

        let entry = """

            ## \(timeString) [Sense:\(sense)]

            \(data)

            """

        if let fileHandle = FileHandle(forWritingAtPath: episodePath) {
            fileHandle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        }

        log("Logged sense event [\(sense)] to \(dateString).md", level: .debug, component: "EpisodeLogger")
    }
}
