import Foundation

/// Represents an update detected in a watched note
struct NoteUpdate {
    let noteName: String
    let htmlContent: String      // Raw HTML content (for writing back)
    let plainTextContent: String // Plain text (for display/processing)
    let timestamp: Date
    let contentHash: String
}

/// Watches specific Apple Notes for changes and triggers callbacks when content changes
final class NoteWatcher {

    // MARK: - Configuration

    /// Notes to watch (by name)
    private let watchedNotes: [String]

    /// How often to poll for changes (in seconds)
    private let pollInterval: TimeInterval

    /// Callback when a note changes
    private let onNoteChanged: (NoteUpdate) -> Void

    // MARK: - State

    /// Last known content hash for each note
    private var contentHashes: [String: String] = [:]

    /// Polling thread
    private var watchThread: Thread?

    /// Flag to stop watching
    private var shouldStop = false

    // MARK: - Initialization

    init(
        watchedNotes: [String] = ["Claude Location Log", "Claude Scratchpad"],
        pollInterval: TimeInterval = 30,
        onNoteChanged: @escaping (NoteUpdate) -> Void
    ) {
        self.watchedNotes = watchedNotes
        self.pollInterval = pollInterval
        self.onNoteChanged = onNoteChanged
    }

    // MARK: - Public Interface

    /// Start watching for note changes
    func start() {
        shouldStop = false

        // Initialize hashes for all watched notes
        for noteName in watchedNotes {
            if let (htmlContent, _) = readNote(named: noteName) {
                contentHashes[noteName] = hashContent(htmlContent)
                log("Initialized watch for '\(noteName)' (hash: \(contentHashes[noteName]?.prefix(8) ?? "nil"))", level: .debug, component: "NoteWatcher")
            } else {
                log("Warning: Could not find note '\(noteName)'", level: .warn, component: "NoteWatcher")
            }
        }

        // Start polling thread
        watchThread = Thread { [weak self] in
            self?.pollLoop()
        }
        watchThread?.name = "NoteWatcher"
        watchThread?.start()

        log("Started watching \(watchedNotes.count) note(s), polling every \(Int(pollInterval))s", level: .info, component: "NoteWatcher")
    }

    /// Stop watching
    func stop() {
        shouldStop = true
        watchThread?.cancel()
        watchThread = nil
        log("Stopped", level: .info, component: "NoteWatcher")
    }

    /// Manually check a specific note (useful for on-demand checks)
    func checkNote(named noteName: String) -> NoteUpdate? {
        guard let (htmlContent, plainText) = readNote(named: noteName) else {
            return nil
        }

        let hash = hashContent(htmlContent)
        return NoteUpdate(
            noteName: noteName,
            htmlContent: htmlContent,
            plainTextContent: plainText,
            timestamp: Date(),
            contentHash: hash
        )
    }

    // MARK: - Private Methods

    private func pollLoop() {
        while !shouldStop {
            Thread.sleep(forTimeInterval: pollInterval)

            if shouldStop { break }

            checkForChanges()
        }
    }

    private func checkForChanges() {
        for noteName in watchedNotes {
            guard let (htmlContent, plainText) = readNote(named: noteName) else {
                continue
            }

            let newHash = hashContent(htmlContent)
            let oldHash = contentHashes[noteName]

            if newHash != oldHash {
                log("Change detected in '\(noteName)'", level: .info, component: "NoteWatcher")
                contentHashes[noteName] = newHash

                let update = NoteUpdate(
                    noteName: noteName,
                    htmlContent: htmlContent,
                    plainTextContent: plainText,
                    timestamp: Date(),
                    contentHash: newHash
                )

                // Dispatch callback on main queue
                DispatchQueue.main.async { [weak self] in
                    self?.onNoteChanged(update)
                }
            }
        }
    }

    private func readNote(named noteName: String) -> (html: String, plainText: String)? {
        let script = """
            tell application "Notes"
                try
                    set targetNote to first note whose name is "\(noteName)"
                    return body of targetNote
                on error
                    return ""
                end try
            end tell
            """

        let process = Process()
        let outputPipe = Pipe()

        // Ensure pipe is closed to prevent file descriptor leaks
        let outputHandle = outputPipe.fileHandleForReading
        defer {
            try? outputHandle.close()
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = outputHandle.readDataToEndOfFile()
            guard let htmlContent = String(data: data, encoding: .utf8), !htmlContent.isEmpty else {
                return nil
            }

            // Return both raw HTML and plain text version
            let plainText = stripHTML(htmlContent)
            return (html: htmlContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    plainText: plainText)
        } catch {
            log("Error reading note '\(noteName)': \(error)", level: .warn, component: "NoteWatcher")
            return nil
        }
    }

    private func stripHTML(_ html: String) -> String {
        // Simple HTML tag removal
        var result = html

        // Replace common HTML entities
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        // Remove HTML tags
        while let range = result.range(of: "<[^>]+>", options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Clean up whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    private func hashContent(_ content: String) -> String {
        // Simple hash using content length and a few character samples
        // For more robust hashing, could use CryptoKit
        var hash = content.count
        for (i, char) in content.enumerated() {
            if i % 10 == 0 {
                hash = hash &+ Int(char.asciiValue ?? 0) &* (i + 1)
            }
        }
        return String(format: "%08x", hash)
    }
}
