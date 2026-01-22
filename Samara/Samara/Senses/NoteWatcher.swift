import Foundation

/// Represents an update detected in a watched note
struct NoteUpdate {
    let noteKey: String
    let noteName: String
    let noteId: String?
    let htmlContent: String      // Raw HTML content (for writing back)
    let plainTextContent: String // Plain text (for display/processing)
    let timestamp: Date
    let contentHash: String
}

/// Watches specific Apple Notes for changes and triggers callbacks when content changes
final class NoteWatcher {

    struct WatchedNote: Hashable {
        let key: String
        let name: String
        let account: String?
        let folder: String?
    }

    struct NoteReadResult {
        let id: String?
        let name: String
        let html: String
        let plainText: String
    }

    typealias NoteReader = (_ note: WatchedNote, _ noteId: String?) -> NoteReadResult?

    // MARK: - Configuration

    /// Notes to watch (by name)
    private let watchedNotes: [WatchedNote]

    /// How often to poll for changes (in seconds)
    private let pollInterval: TimeInterval

    /// Callback when a note changes
    private let onNoteChanged: (NoteUpdate) -> Void

    /// Read note content by name (injectable for tests)
    private let noteReader: NoteReader?

    /// Optional state file for storing note IDs by key
    private let noteIdStorePath: String?

    // MARK: - State

    /// Last known content hash for each note (keyed by watched note key)
    private var contentHashes: [String: String] = [:]

    /// Persisted note IDs by key
    private var noteIds: [String: String] = [:]

    /// Polling thread
    private var watchThread: Thread?

    /// Flag to stop watching
    private var shouldStop = false

    // MARK: - Initialization

    init(
        watchedNotes: [WatchedNote],
        pollInterval: TimeInterval = 30,
        noteIdStorePath: String? = nil,
        noteReader: NoteReader? = nil,
        onNoteChanged: @escaping (NoteUpdate) -> Void
    ) {
        self.watchedNotes = watchedNotes
        self.pollInterval = pollInterval
        self.noteIdStorePath = noteIdStorePath
        self.onNoteChanged = onNoteChanged
        self.noteReader = noteReader

        loadNoteIds()
    }

    convenience init(
        watchedNotes: [String] = ["Claude Location Log", "Claude Scratchpad"],
        pollInterval: TimeInterval = 30,
        noteReader: ((String) -> (html: String, plainText: String)?)? = nil,
        onNoteChanged: @escaping (NoteUpdate) -> Void
    ) {
        let targets = watchedNotes.map { WatchedNote(key: $0, name: $0, account: nil, folder: nil) }
        let adapter: NoteReader? = noteReader.map { reader in
            return { note, _ in
                guard let result = reader(note.name) else { return nil }
                return NoteReadResult(id: nil, name: note.name, html: result.html, plainText: result.plainText)
            }
        }
        self.init(
            watchedNotes: targets,
            pollInterval: pollInterval,
            noteIdStorePath: nil,
            noteReader: adapter,
            onNoteChanged: onNoteChanged
        )
    }

    // MARK: - Public Interface

    /// Start watching for note changes
    func start() {
        shouldStop = false

        // Initialize hashes for all watched notes
        for note in watchedNotes {
            if let result = resolveNote(for: note) {
                contentHashes[note.key] = hashContent(result.html)
                log("Initialized watch for '\(note.name)' (key: \(note.key))",
                    level: .debug,
                    component: "NoteWatcher")
            } else {
                log("Warning: Could not find note '\(note.name)' (key: \(note.key))",
                    level: .warn,
                    component: "NoteWatcher")
            }
        }

        // Start polling thread
        watchThread = Thread { [weak self] in
            self?.pollLoop()
        }
        watchThread?.name = "NoteWatcher"
        watchThread?.start()

        log("Started watching \(watchedNotes.count) note(s), polling every \(Int(pollInterval))s",
            level: .info,
            component: "NoteWatcher")
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
        if let note = watchedNotes.first(where: { $0.name == noteName }),
           let result = resolveNote(for: note) {
            let hash = hashContent(result.html)
            return makeUpdate(note: note, result: result, hash: hash)
        }

        let temp = WatchedNote(key: noteName, name: noteName, account: nil, folder: nil)
        guard let result = resolveNote(for: temp) else {
            return nil
        }

        let hash = hashContent(result.html)
        return makeUpdate(note: temp, result: result, hash: hash)
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
        for note in watchedNotes {
            guard let result = resolveNote(for: note) else {
                continue
            }

            let newHash = hashContent(result.html)
            let oldHash = contentHashes[note.key]

            if newHash != oldHash {
                log("Change detected in '\(result.name)'", level: .info, component: "NoteWatcher")
                contentHashes[note.key] = newHash

                let update = makeUpdate(note: note, result: result, hash: newHash)

                // Dispatch callback on main queue
                DispatchQueue.main.async { [weak self] in
                    self?.onNoteChanged(update)
                }
            }
        }
    }

    private func resolveNote(for note: WatchedNote) -> NoteReadResult? {
        let storedId = noteIds[note.key]
        let result = noteReader?(note, storedId) ?? readNote(note: note, storedId: storedId)
        guard let result else { return nil }

        if let id = result.id, id != storedId {
            noteIds[note.key] = id
            persistNoteIds()
        }

        return result
    }

    private func makeUpdate(note: WatchedNote, result: NoteReadResult, hash: String) -> NoteUpdate {
        NoteUpdate(
            noteKey: note.key,
            noteName: result.name,
            noteId: result.id,
            htmlContent: result.html,
            plainTextContent: result.plainText,
            timestamp: Date(),
            contentHash: hash
        )
    }

    private func readNote(note: WatchedNote, storedId: String?) -> NoteReadResult? {
        if let storedId, let result = readNoteById(storedId) {
            return result
        }

        if let result = readNoteByName(note.name, account: note.account, folder: note.folder) {
            return result
        }

        guard let account = note.account, let folder = note.folder else {
            return nil
        }

        return readUniqueNote(account: account, folder: folder)
    }

    private func readNoteById(_ noteId: String) -> NoteReadResult? {
        let escapedId = escapeAppleScriptString(noteId)
        let script = """
            tell application "Notes"
                try
                    set targetNote to note id "\(escapedId)"
                    return (id of targetNote) & linefeed & (name of targetNote) & linefeed & (body of targetNote)
                on error
                    return ""
                end try
            end tell
            """
        return runNoteScript(script)
    }

    private func readNoteByName(_ noteName: String, account: String?, folder: String?) -> NoteReadResult? {
        let escapedName = escapeAppleScriptString(noteName)
        let script: String

        if let account = account, let folder = folder {
            let escapedAccount = escapeAppleScriptString(account)
            let escapedFolder = escapeAppleScriptString(folder)
            script = """
                tell application "Notes"
                    try
                        set targetNote to first note of folder "\(escapedFolder)" of account "\(escapedAccount)" whose name is "\(escapedName)"
                        return (id of targetNote) & linefeed & (name of targetNote) & linefeed & (body of targetNote)
                    on error
                        return ""
                    end try
                end tell
                """
        } else {
            script = """
                tell application "Notes"
                    try
                        set targetNote to first note whose name is "\(escapedName)"
                        return (id of targetNote) & linefeed & (name of targetNote) & linefeed & (body of targetNote)
                    on error
                        return ""
                    end try
                end tell
                """
        }

        return runNoteScript(script)
    }

    private func readUniqueNote(account: String, folder: String) -> NoteReadResult? {
        let escapedAccount = escapeAppleScriptString(account)
        let escapedFolder = escapeAppleScriptString(folder)
        let script = """
            tell application "Notes"
                try
                    set folderNotes to notes of folder "\(escapedFolder)" of account "\(escapedAccount)"
                    if (count of folderNotes) is 1 then
                        set targetNote to item 1 of folderNotes
                        return (id of targetNote) & linefeed & (name of targetNote) & linefeed & (body of targetNote)
                    end if
                    return ""
                on error
                    return ""
                end try
            end tell
            """
        return runNoteScript(script)
    }

    private func runNoteScript(_ script: String) -> NoteReadResult? {
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
            guard let rawOutput = String(data: data, encoding: .utf8),
                  let parsed = parseNoteResponse(rawOutput) else {
                return nil
            }

            return parsed
        } catch {
            log("Error reading note via AppleScript: \(error)", level: .warn, component: "NoteWatcher")
            return nil
        }
    }

    private func parseNoteResponse(_ output: String) -> NoteReadResult? {
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)

        let parts = normalized.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3 else {
            return nil
        }

        let idRaw = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let html = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !html.isEmpty else {
            return nil
        }

        let plainText = stripHTML(html)
        return NoteReadResult(
            id: idRaw.isEmpty ? nil : idRaw,
            name: name.isEmpty ? "Unknown Note" : name,
            html: html,
            plainText: plainText
        )
    }

    private func loadNoteIds() {
        guard let noteIdStorePath else { return }
        let url = URL(fileURLWithPath: noteIdStorePath)
        guard let data = try? Data(contentsOf: url) else { return }

        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            noteIds = decoded
        }
    }

    private func persistNoteIds() {
        guard let noteIdStorePath else { return }
        let url = URL(fileURLWithPath: noteIdStorePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(noteIds) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
