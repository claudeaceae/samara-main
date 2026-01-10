import Foundation

/// Represents a memory from the SQLite database
struct Memory {
    let id: Int
    let content: String
    let context: String?
    let memoryType: String
    let episodeDate: String?
    let themes: [String]
}

/// Reads memory files to build context for Claude invocations
final class MemoryContext {
    private let mindPath: String
    private let dbPath: String

    /// Native SQLite + FTS5 memory database
    private var memoryDB: MemoryDatabase?

    /// Whether to use native FTS5 (true) or fall back to subprocess (false)
    private var useNativeFTS: Bool = true

    init() {
        self.mindPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
            .path
        self.dbPath = (mindPath as NSString).appendingPathComponent("memory.db")

        // Initialize native database
        initializeMemoryDatabase()
    }

    /// Initialize the native memory database
    private func initializeMemoryDatabase() {
        let semanticDbPath = (mindPath as NSString).appendingPathComponent("semantic/memory.db")
        memoryDB = MemoryDatabase(dbPath: semanticDbPath)

        do {
            try memoryDB?.open()
            log("Native FTS5 memory database initialized", level: .info, component: "MemoryContext")
        } catch {
            log("Failed to initialize native FTS5, falling back to subprocess: \(error)",
                level: .warn, component: "MemoryContext")
            useNativeFTS = false
            memoryDB = nil
        }
    }

    /// Builds a context string from key memory files
    ///
    /// Design principle (2025-12-22): Load full files, no truncation.
    /// Token budget is ~36K for all core memory (~18% of 200K context).
    /// Coherence > marginal token savings. Future scaling via retrieval tools.
    ///
    /// - Parameter isCollaboratorChat: If false, excludes collaborator's personal profile
    ///   for privacy protection (used in group chats or non-collaborator 1:1s)
    func buildContext(isCollaboratorChat: Bool = true) -> String {
        var sections: [String] = []

        // Identity - full, essential context
        if let identity = readFile("identity.md") {
            sections.append("### Identity\n\(identity)")
        }

        // Decisions - full, critical for behavioral consistency across contexts
        if let decisions = readFile("memory/decisions.md") {
            sections.append("### Architectural Decisions\n\(decisions)")
        }

        // About collaborator - ONLY include for collaborator chats (privacy protection)
        // Try new people/ structure first, fall back to legacy about-{name}.md
        if isCollaboratorChat {
            let collaboratorName = config.collaborator.name
            let collaboratorLower = collaboratorName.lowercased()
            let peopleFile = "memory/people/\(collaboratorLower)/profile.md"
            let legacyFile = "memory/about-\(collaboratorLower).md"
            if let aboutContent = readFile(peopleFile) ?? readFile(legacyFile) ?? readFile("memory/about-e.md") {
                sections.append("### About \(collaboratorName)\n\(aboutContent)")
            }
        }

        // Goals - full
        if let goals = readFile("goals.md") {
            sections.append("### Goals\n\(goals)")
        }

        // Capabilities - full
        if let capabilities = readFile("capabilities/inventory.md") {
            sections.append("### Capabilities\n\(capabilities)")
        }

        // Learnings - full (append-only, recent at bottom)
        if let learnings = readFile("memory/learnings.md") {
            sections.append("### Learnings\n\(learnings)")
        }

        // Observations - full (append-only, recent at bottom)
        if let observations = readFile("memory/observations.md") {
            sections.append("### Self-Observations\n\(observations)")
        }

        // Questions - full (append-only, recent at bottom)
        if let questions = readFile("memory/questions.md") {
            sections.append("### Open Questions\n\(questions)")
        }

        // Current working memory
        if let current = readFile("scratch/current.md") {
            sections.append("### Current Session\n\(current)")
        }

        // Today's episode - full, resets daily
        let today = todayEpisodePath()
        if let episode = readFile(today) {
            sections.append("### Today's Journal\n\(episode)")
        }

        // Location awareness - current state and patterns
        if let locationSummary = buildLocationSummary() {
            sections.append("### Location Awareness\n\(locationSummary)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Loads profiles for specified handles (phone/email) to check permissions
    /// Returns a formatted string with relevant person profiles
    func loadParticipantProfiles(handles: [String]) -> String? {
        var profiles: [String] = []

        // Try to find profile by handle - need to search all people directories
        let peopleDir = (mindPath as NSString).appendingPathComponent("memory/people")

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: peopleDir) else {
            return nil
        }

        for personDir in contents where personDir != "_template" && !personDir.hasPrefix(".") {
            let profilePath = "memory/people/\(personDir)/profile.md"
            if let profile = readFile(profilePath) {
                // Check if any handle appears in the profile (simple check)
                // Or if the directory name matches part of a handle
                for handle in handles {
                    let handleLower = handle.lowercased()
                    let dirLower = personDir.lowercased()
                    if profile.lowercased().contains(handleLower) || handleLower.contains(dirLower) {
                        profiles.append("### \(personDir)\n\(profile)")
                        break
                    }
                }
            }
        }

        guard !profiles.isEmpty else { return nil }
        return profiles.joined(separator: "\n\n")
    }

    /// Builds context with cross-temporal linking for a specific conversation
    ///
    /// This version includes semantically related past conversations based on
    /// the current message content. Uses Chroma vector search.
    func buildContextWithCrossTemporal(currentMessage: String) -> String {
        var context = buildContext()

        // Get related past context via Chroma
        if let relatedContext = findRelatedPastContext(for: currentMessage) {
            context += "\n\n" + relatedContext
        }

        return context
    }

    /// Calls the find-related-context script to get semantically similar past conversations
    /// Used by ClaudeInvoker for cross-temporal context in message responses
    func findRelatedPastContext(for query: String) -> String? {
        let scriptPath = (mindPath as NSString).appendingPathComponent("bin/find-related-context")

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return nil
        }

        let process = Process()
        let outputPipe = Pipe()

        // Ensure pipe is closed to prevent file descriptor leaks
        let outputHandle = outputPipe.fileHandleForReading
        defer {
            try? outputHandle.close()
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, query]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        // Set environment for the script
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        process.environment = env

        do {
            try process.run()

            // Wait with timeout to prevent blocking forever
            let timeout: TimeInterval = 10
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                log("Cross-temporal search timeout after \(Int(timeout))s - killing process", level: .warn, component: "MemoryContext")
                process.terminate()
                return nil
            }

            let outputData = outputHandle.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8),
                  !output.isEmpty,
                  output.contains("match)") else {  // Only include if we found matches
                return nil
            }

            return output
        } catch {
            log("Cross-temporal search failed: \(error)", level: .warn, component: "MemoryContext")
            return nil
        }
    }

    /// Reads a file relative to the mind path
    private func readFile(_ relativePath: String) -> String? {
        let fullPath = (mindPath as NSString).appendingPathComponent(relativePath)
        return try? String(contentsOfFile: fullPath, encoding: .utf8)
    }

    /// Returns the path to today's episode file
    private func todayEpisodePath() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return "memory/episodes/\(today).md"
    }

    // MARK: - Instruction File Loading

    /// Reads an instruction file and substitutes placeholders
    /// - Parameters:
    ///   - filename: Name of the file in instructions/ directory (e.g., "imessage.md")
    ///   - substitutions: Dictionary of placeholder -> value pairs (e.g., ["COLLABORATOR": "É"])
    /// - Returns: File content with placeholders substituted, or nil if file not found
    func readInstructionFile(_ filename: String, substitutions: [String: String] = [:]) -> String? {
        guard var content = readFile("instructions/\(filename)") else {
            return nil
        }

        // Apply substitutions for placeholders like {{COLLABORATOR}}
        for (placeholder, value) in substitutions {
            content = content.replacingOccurrences(of: "{{\(placeholder)}}", with: value)
        }

        return content
    }

    /// Default iMessage instructions as fallback if file loading fails
    static let defaultIMessageInstructions = """
        ## Response Instructions
        Your entire output will be sent as an iMessage. Respond naturally and concisely.
        - Keep responses brief (this is texting)
        - DO NOT narrate actions or use the message script
        - DO NOT use markdown formatting - Apple Messages displays it literally
        - To send images: ~/.claude-mind/bin/send-image /path/to/file
        - To take photos: ~/.claude-mind/bin/look -s
        """

    /// Builds location awareness summary from state files
    private func buildLocationSummary() -> String? {
        var lines: [String] = []

        // Current location
        if let locationData = readFile("state/location.json"),
           let data = locationData.data(using: .utf8),
           let location = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let lat = location["lat"] as? Double,
               let lon = location["lon"] as? Double {
                let timestamp = location["timestamp"] as? String ?? "unknown"
                lines.append("Current: \(lat), \(lon) (as of \(timestamp))")
            }
        }

        // Today's trips
        if let tripsData = readFile("state/trips.jsonl") {
            let today = todayEpisodePath().replacingOccurrences(of: "memory/episodes/", with: "")
                .replacingOccurrences(of: ".md", with: "")
            let todayTrips = tripsData.components(separatedBy: "\n")
                .filter { $0.contains(today) && !$0.isEmpty }

            if !todayTrips.isEmpty {
                lines.append("Trips today: \(todayTrips.count)")
                // Show last trip
                if let lastTrip = todayTrips.last,
                   let data = lastTrip.data(using: .utf8),
                   let trip = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let start = trip["start_place"] as? String ?? "unknown"
                    let end = trip["end_place"] as? String ?? "unknown"
                    let distance = trip["distance_m"] as? Int ?? 0
                    lines.append("Last trip: \(start) → \(end) (\(distance)m)")
                }
            }
        }

        // Learned patterns
        if let patternsData = readFile("state/location-patterns.json"),
           let data = patternsData.data(using: .utf8),
           let patterns = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            if let homeDeparture = patterns["home_departure"] as? [String: Any],
               let weekday = homeDeparture["weekday"] as? [String: Any],
               let typicalTime = weekday["typical_time"] as? String {
                lines.append("Typical departure: ~\(typicalTime) on weekdays")
            }

            if let homeReturn = patterns["home_return"] as? [String: Any],
               let weekday = homeReturn["weekday"] as? [String: Any],
               let typicalTime = weekday["typical_time"] as? String {
                lines.append("Typical return: ~\(typicalTime) on weekdays")
            }
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// Abbreviates content to a maximum number of lines (from the START)
    private func abbreviate(_ content: String, maxLines: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        if lines.count <= maxLines {
            return content
        }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n[...]"
    }

    /// Gets the LAST N lines of content (for episodes where recent entries matter most)
    private func lastLines(_ content: String, maxLines: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        if lines.count <= maxLines {
            return content
        }
        return "[...]\n" + lines.suffix(maxLines).joined(separator: "\n")
    }

    // MARK: - SQLite Memory Search

    /// Find related memories using FTS5 search
    /// - Parameters:
    ///   - query: Search terms to find related memories
    ///   - limit: Maximum number of results (default 5)
    /// - Returns: Array of related Memory objects
    func findRelatedMemories(query: String, limit: Int = 5) -> [Memory] {
        // Try native FTS5 first
        if useNativeFTS, let db = memoryDB {
            return findRelatedMemoriesNative(query: query, limit: limit, db: db)
        }

        // Fall back to subprocess method
        return findRelatedMemoriesSubprocess(query: query, limit: limit)
    }

    /// Native FTS5 search using MemoryDatabase
    private func findRelatedMemoriesNative(query: String, limit: Int, db: MemoryDatabase) -> [Memory] {
        do {
            let results = try db.search(query: query, limit: limit)

            // Convert MemoryDatabase.MemoryEntry to Memory
            return results.map { entry in
                Memory(
                    id: Int(entry.id),
                    content: entry.content,
                    context: entry.context,
                    memoryType: entry.memoryType,
                    episodeDate: entry.episodeDate,
                    themes: []  // Native DB doesn't track themes yet
                )
            }
        } catch {
            log("Native FTS search failed: \(error)", level: .warn, component: "MemoryContext")
            // Fall back to subprocess on error
            return findRelatedMemoriesSubprocess(query: query, limit: limit)
        }
    }

    /// Subprocess-based FTS5 search (legacy fallback)
    private func findRelatedMemoriesSubprocess(query: String, limit: Int) -> [Memory] {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        // Extract meaningful search terms from query
        let searchTerms = extractSearchTerms(from: query)
        guard !searchTerms.isEmpty else {
            return []
        }

        // Build FTS query - use OR for better recall
        let ftsQuery = searchTerms.joined(separator: " OR ")

        // Run sqlite3 command for FTS search
        let process = Process()
        let outputPipe = Pipe()

        // Ensure pipe is closed to prevent file descriptor leaks
        let outputHandle = outputPipe.fileHandleForReading
        defer {
            try? outputHandle.close()
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath,
            """
            SELECT
                m.id,
                m.content,
                m.context,
                m.memory_type,
                m.episode_date,
                COALESCE(GROUP_CONCAT(DISTINCT t.name), '') as themes
            FROM memories_fts
            JOIN memories m ON memories_fts.rowid = m.id
            LEFT JOIN memory_themes mt ON m.id = mt.memory_id
            LEFT JOIN themes t ON mt.theme_id = t.id
            WHERE memories_fts MATCH '\(ftsQuery)'
            GROUP BY m.id
            ORDER BY rank
            LIMIT \(limit);
            """
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // Wait with timeout to prevent blocking forever
            let timeout: TimeInterval = 5
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                log("FTS search timeout after \(Int(timeout))s - killing process", level: .warn, component: "MemoryContext")
                process.terminate()
                return []
            }

            let outputData = outputHandle.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
                return []
            }

            return parseMemoriesFromSqlite(output)
        } catch {
            log("FTS search failed: \(error)", level: .warn, component: "MemoryContext")
            return []
        }
    }

    /// Extract meaningful search terms from a query string
    private func extractSearchTerms(from query: String) -> [String] {
        // Remove common stop words and short words
        let stopWords = Set(["a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
                             "have", "has", "had", "do", "does", "did", "will", "would", "could",
                             "should", "may", "might", "must", "shall", "can", "to", "of", "in",
                             "for", "on", "with", "at", "by", "from", "as", "or", "and", "but",
                             "if", "then", "so", "than", "that", "this", "these", "those", "it",
                             "its", "my", "your", "his", "her", "their", "our", "me", "you", "him",
                             "her", "them", "us", "what", "which", "who", "whom", "whose", "where",
                             "when", "why", "how", "i", "we", "he", "she", "they", "just", "very",
                             "really", "actually", "basically", "literally", "probably", "maybe"])

        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        // Return unique terms, limited to first 5 meaningful words
        return Array(Set(words)).prefix(5).map { String($0) }
    }

    /// Parse sqlite3 output into Memory objects
    private func parseMemoriesFromSqlite(_ output: String) -> [Memory] {
        var memories: [Memory] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            // SQLite default separator is |
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 6 else { continue }

            let id = Int(fields[0]) ?? 0
            let content = fields[1]
            let context = fields[2].isEmpty ? nil : fields[2]
            let memoryType = fields[3]
            let episodeDate = fields[4].isEmpty ? nil : fields[4]
            let themes = fields[5].components(separatedBy: ",").filter { !$0.isEmpty }

            memories.append(Memory(
                id: id,
                content: content,
                context: context,
                memoryType: memoryType,
                episodeDate: episodeDate,
                themes: themes
            ))
        }

        return memories
    }

    /// Build a formatted section of related memories for context injection
    func buildRelatedMemoriesSection(for query: String) -> String? {
        let memories = findRelatedMemories(query: query)
        guard !memories.isEmpty else { return nil }

        var lines: [String] = []
        for memory in memories {
            var line = "- "
            if let date = memory.episodeDate {
                line += "[\(date)] "
            }
            line += memory.content
            if !memory.themes.isEmpty {
                line += " (themes: \(memory.themes.joined(separator: ", ")))"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}
