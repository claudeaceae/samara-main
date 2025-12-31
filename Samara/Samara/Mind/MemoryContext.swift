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

    init() {
        self.mindPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
            .path
        self.dbPath = (mindPath as NSString).appendingPathComponent("memory.db")
    }

    /// Builds a context string from key memory files
    ///
    /// Design principle (2025-12-22): Load full files, no truncation.
    /// Token budget is ~36K for all core memory (~18% of 200K context).
    /// Coherence > marginal token savings. Future scaling via retrieval tools.
    func buildContext() -> String {
        var sections: [String] = []

        // Identity - full, essential context
        if let identity = readFile("identity.md") {
            sections.append("### Identity\n\(identity)")
        }

        // Decisions - full, critical for behavioral consistency across contexts
        if let decisions = readFile("memory/decisions.md") {
            sections.append("### Architectural Decisions\n\(decisions)")
        }

        // About collaborator - full, relationship context
        // Try config-driven filename first, fall back to legacy about-e.md
        let collaboratorName = config.collaborator.name
        let aboutFile = "memory/about-\(collaboratorName.lowercased()).md"
        if let aboutContent = readFile(aboutFile) ?? readFile("memory/about-e.md") {
            sections.append("### About \(collaboratorName)\n\(aboutContent)")
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

        return sections.joined(separator: "\n\n")
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
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8),
                  !output.isEmpty,
                  output.contains("match)") else {  // Only include if we found matches
                return nil
            }

            return output
        } catch {
            print("[MemoryContext] Cross-temporal search failed: \(error)")
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
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
                return []
            }

            return parseMemoriesFromSqlite(output)
        } catch {
            print("[MemoryContext] FTS search failed: \(error)")
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
