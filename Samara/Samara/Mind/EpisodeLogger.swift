import Foundation

/// Logs conversations to daily episode files AND the unified event stream
final class EpisodeLogger {
    private let episodesPath: String
    private let streamPath: String
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    init() {
        let mindPath = MindPaths.mindPath()
        self.episodesPath = (mindPath as NSString).appendingPathComponent("memory/episodes")
        self.streamPath = (mindPath as NSString).appendingPathComponent("bin/stream")

        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        self.timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        ensureEpisodesDirectory()
    }

    // MARK: - Stream Integration

    /// Write event to the unified stream for contiguous memory
    private func writeToStream(
        surface: String,
        eventType: String = "interaction",
        direction: String,
        summary: String,
        content: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        // Only attempt if stream command exists
        guard FileManager.default.isExecutableFile(atPath: streamPath) else {
            return
        }

        var args = [
            "write",
            "--surface", surface,
            "--type", eventType,
            "--direction", direction,
            "--summary", String(summary.prefix(200))
        ]

        if let content = content {
            args.append(contentsOf: ["--content", String(content.prefix(2000))])
        }

        if let metadata = metadata {
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                args.append(contentsOf: ["--metadata", jsonString])
            }
        }

        // Run asynchronously to not block episode writing
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.streamPath)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Silent failure - stream is supplementary to episode logs
            }
        }
    }

    private func ensureEpisodesDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: episodesPath, withIntermediateDirectories: true)
        } catch {
            log("Failed to create episodes directory: \(error)", level: .warn, component: "EpisodeLogger")
        }
    }

    private func surfaceForSource(_ source: String) -> String {
        var normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("sense:") {
            normalized = String(normalized.dropFirst("sense:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch normalized {
        case "imessage":
            return "imessage"
        case "x", "twitter":
            return "x"
        case "bluesky":
            return "bluesky"
        case "email":
            return "email"
        case "calendar", "meeting_prep", "meeting_debrief", "meeting":
            return "calendar"
        case "location":
            return "location"
        case "webhook":
            return "webhook"
        case "system", "alert":
            return "system"
        case "wake":
            return "wake"
        default:
            return "sense"
        }
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

        MemoryContext.invalidateEpisodeCache()

        // Dual-write to unified event stream
        let surfaceType = surfaceForSource(source)
        writeToStream(
            surface: surfaceType,
            eventType: "interaction",
            direction: "inbound",
            summary: "\(sender): \(String(message.prefix(100)))",
            content: "**\(sender):** \(message)\n\n**Claude:** \(response)",
            metadata: ["source": source]
        )

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

        MemoryContext.invalidateEpisodeCache()

        // Dual-write to unified event stream
        writeToStream(
            surface: "system",
            eventType: "system",
            direction: "internal",
            summary: "Note: \(String(note.prefix(150)))",
            content: note,
            metadata: ["source": source]
        )
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

        MemoryContext.invalidateEpisodeCache()

        // Dual-write to unified event stream
        let surfaceType: String
        switch source.lowercased() {
        case "imessage": surfaceType = "imessage"
        case "location": surfaceType = "location"
        case "wake": surfaceType = "wake"
        case "alert": surfaceType = "system"
        default: surfaceType = "sense"
        }
        writeToStream(
            surface: surfaceType,
            eventType: "interaction",
            direction: "outbound",
            summary: "Claude: \(String(message.prefix(150)))",
            content: message,
            metadata: ["source": source]
        )

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

        MemoryContext.invalidateEpisodeCache()

        // Dual-write to unified event stream
        let surfaceType: String
        switch sense.lowercased() {
        case "location": surfaceType = "location"
        case "webhook": surfaceType = "webhook"
        case "x", "twitter": surfaceType = "x"
        case "bluesky": surfaceType = "bluesky"
        case "email": surfaceType = "email"
        case "calendar", "meeting_prep", "meeting_debrief", "meeting": surfaceType = "calendar"
        default: surfaceType = "sense"
        }
        writeToStream(
            surface: surfaceType,
            eventType: "sense",
            direction: "inbound",
            summary: "Sense[\(sense)]: \(String(data.prefix(150)))",
            content: data,
            metadata: ["sense_type": sense]
        )

        log("Logged sense event [\(sense)] to \(dateString).md", level: .debug, component: "EpisodeLogger")
    }
}
