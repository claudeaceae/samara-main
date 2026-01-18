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
        self.mindPath = MindPaths.mindPath()
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

    // MARK: - Size Limits

    /// Maximum lines for large append-only files (learnings, observations, decisions)
    /// Reduced from 200 to 75 to stay within prompt limits (2026-01-15)
    private let maxLinesForLargeFiles = 75

    /// Maximum lines for episode files
    private let maxLinesForEpisode = 150

    /// Builds a context string from key memory files
    ///
    /// Design principle (2025-12-22): Load full files, no truncation.
    /// UPDATE (2026-01-14): Added size limits as safety net - files can grow very large
    /// and exceed context limits. Now truncates to recent entries for append-only files.
    ///
    /// - Parameter isCollaboratorChat: If false, excludes collaborator's personal profile
    ///   for privacy protection (used in group chats or non-collaborator 1:1s)
    func buildContext(isCollaboratorChat: Bool = true) -> String {
        var sections: [String] = []

        // HOT DIGEST FIRST - cross-surface recent context
        // This ensures iMessage sessions know about CLI work and vice versa
        if let hotDigest = buildHotDigest() {
            sections.append(hotDigest)
        }

        // Identity - full, essential context
        if let identity = readFile("identity.md") {
            sections.append("### Identity\n\(identity)")
        }

        // Decisions - truncated to recent (append-only, grows large)
        if let decisions = readFile("memory/decisions.md") {
            let truncated = lastLines(decisions, maxLines: maxLinesForLargeFiles)
            sections.append("### Architectural Decisions\n\(truncated)")
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

        // Goals - full (usually small)
        if let goals = readFile("goals.md") {
            sections.append("### Goals\n\(goals)")
        }

        // Capabilities - abbreviated (file can be 800KB+, only load summary)
        // Full capabilities can be referenced on-demand via /capability skill
        if let capabilities = readFile("capabilities/inventory.md") {
            let abbreviated = abbreviate(capabilities, maxLines: 100)
            sections.append("### Capabilities (summary)\n\(abbreviated)")
        }

        // Learnings - truncated to recent (append-only, grows large)
        if let learnings = readFile("memory/learnings.md") {
            let truncated = lastLines(learnings, maxLines: maxLinesForLargeFiles)
            sections.append("### Learnings\n\(truncated)")
        }

        // Observations - truncated to recent (append-only, grows large)
        if let observations = readFile("memory/observations.md") {
            let truncated = lastLines(observations, maxLines: maxLinesForLargeFiles)
            sections.append("### Self-Observations\n\(truncated)")
        }

        // Questions - truncated to recent (append-only)
        if let questions = readFile("memory/questions.md") {
            let truncated = lastLines(questions, maxLines: 100)
            sections.append("### Open Questions\n\(truncated)")
        }

        // Current working memory
        if let current = readFile("scratch/current.md") {
            sections.append("### Current Session\n\(current)")
        }

        // Today's episode - truncated to recent entries
        let today = todayEpisodePath()
        if let episode = readFile(today) {
            let truncated = lastLines(episode, maxLines: maxLinesForEpisode)
            sections.append("### Today's Journal\n\(truncated)")
        }

        // Location awareness - current state and patterns
        if let locationSummary = buildLocationSummary() {
            sections.append("### Location Awareness\n\(locationSummary)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Builds a LIGHTWEIGHT context for sense events and social media handlers
    ///
    /// This is much smaller than buildContext() - designed for X/Bluesky/GitHub events
    /// where we don't need full memory, just identity + semantic search for relevance.
    ///
    /// - Parameters:
    ///   - query: Optional search query to find related memories (e.g., tweet content)
    ///   - includeCapabilities: Whether to include the capabilities inventory
    /// - Returns: Minimal context string suitable for social media responses
    func buildLightContext(query: String? = nil, includeCapabilities: Bool = false) -> String {
        var sections: [String] = []

        // Identity - always essential
        if let identity = readFile("identity.md") {
            sections.append("### Identity\n\(identity)")
        }

        // Goals - brief, helps with voice/priorities
        if let goals = readFile("goals.md") {
            // Just first 50 lines for quick context
            let abbreviated = abbreviate(goals, maxLines: 50)
            sections.append("### Goals\n\(abbreviated)")
        }

        // Capabilities - optional, useful for knowing what actions are possible
        if includeCapabilities, let capabilities = readFile("capabilities/inventory.md") {
            // Abbreviated - just the key sections
            let abbreviated = abbreviate(capabilities, maxLines: 100)
            sections.append("### Capabilities\n\(abbreviated)")
        }

        // If we have a query, add relevant memories via semantic search
        if let query = query, !query.isEmpty {
            // FTS5 search
            if let relatedMemories = buildRelatedMemoriesSection(for: query) {
                sections.append("### Related Memories\n\(relatedMemories)")
            }

            // Chroma semantic search (if configured)
            if let semanticContext = findRelatedPastContext(for: query) {
                sections.append(semanticContext)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Smart Context Building (RAG-style)

    /// Context cache for avoiding redundant file reads
    private static var contextCache: ContextCache?

    /// Get or create the shared context cache
    private var cache: ContextCache {
        if MemoryContext.contextCache == nil {
            MemoryContext.contextCache = ContextCache(defaultTTL: 300, maxEntries: 50)
        }
        return MemoryContext.contextCache!
    }

    /// Builds CORE context - minimal base that's always loaded (~3K tokens)
    /// Establishes identity and voice without loading full memory files
    ///
    /// - Returns: Core context string with identity summary, goals, and pointers
    func buildCoreContext() -> String {
        var sections: [String] = []

        // Current datetime for temporal awareness
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let currentTime = formatter.string(from: Date())
        sections.append("## Current Time\n\(currentTime)")

        // Identity summary (first 50 lines for essence)
        if let identity = readFile("identity.md") {
            let summary = abbreviate(identity, maxLines: 50)
            sections.append("## Identity\n\(summary)")
        }

        // Active goals only (abbreviated)
        if let goals = readFile("goals.md") {
            let abbreviated = abbreviate(goals, maxLines: 30)
            sections.append("## Goals\n\(abbreviated)")
        }

        // Collaborator context (brief)
        let collaboratorName = config.collaborator.name
        sections.append("## Collaborator\nYou are working with \(collaboratorName), your human collaborator.")

        // Pointers to available resources (not loaded)
        sections.append("""
            ## Available Resources (load on demand)

            These resources are available but not loaded. Reference them when needed:

            - **Capabilities:** Full inventory at ~/.claude-mind/capabilities/inventory.md
              Use /capability skill to check if something is possible

            - **Memory Search:** Use /recall for semantic memory lookup
              FTS5 and Chroma indexes available for past conversations

            - **Person Profiles:** Located at ~/.claude-mind/memory/people/{name}/
              Load specific profiles when discussing individuals

            - **Past Decisions:** Architectural decisions at ~/.claude-mind/memory/decisions.md
              Search when asked "why did we..." or about past choices

            - **Learnings & Observations:** Recent insights at ~/.claude-mind/memory/
              Search when reflecting on patterns or growth
            """)

        return sections.joined(separator: "\n\n")
    }

    /// Builds SMART context based on analyzed needs (~5-10K tokens)
    /// Uses ContextRouter results to load only relevant modules
    ///
    /// - Parameters:
    ///   - needs: ContextNeeds from ContextRouter analysis
    ///   - isCollaboratorChat: Privacy flag for collaborator profile loading
    /// - Returns: Targeted context string
    func buildSmartContext(needs: ContextRouter.ContextNeeds, isCollaboratorChat: Bool = true) -> String {
        var sections: [String] = []

        // Always start with core context
        sections.append(buildCoreContext())

        // Load required modules based on needs
        for module in needs.requiredModules {
            if let moduleContent = loadModule(module, isCollaboratorChat: isCollaboratorChat) {
                sections.append(moduleContent)
            }
        }

        // Add FTS5 search results for queries
        if !needs.searchQueries.isEmpty {
            let combinedQuery = needs.searchQueries.joined(separator: " ")
            if let searchResults = buildRelatedMemoriesSection(for: combinedQuery) {
                sections.append("## Related Memories\n\(searchResults)")
            }

            // Only add Chroma if FTS5 returned sparse results AND we have budget
            // This is the "lazy Chroma" optimization
            let ftsCount = findRelatedMemories(query: combinedQuery).count
            if ftsCount < 3 && needs.estimatedTokens < 8000 {
                if let chromaResults = findRelatedPastContext(for: combinedQuery) {
                    sections.append(chromaResults)
                }
            }
        }

        let result = sections.joined(separator: "\n\n")

        // Log token estimate
        let estimatedTokens = Int(Double(result.count) * 0.30)
        log("Smart context built: ~\(estimatedTokens) tokens, \(needs.requiredModules.count) modules",
            level: .debug, component: "MemoryContext")

        return result
    }

    /// Load a specific context module
    ///
    /// - Parameters:
    ///   - module: The context module to load
    ///   - isCollaboratorChat: Privacy flag for person profiles
    /// - Returns: Formatted module content, or nil if not available
    func loadModule(_ module: ContextRouter.ContextModule, isCollaboratorChat: Bool = true) -> String? {
        switch module {
        case .capabilities:
            return loadCapabilitiesModule()

        case .decisions:
            return loadDecisionsModule()

        case .learnings:
            return loadLearningsModule()

        case .observations:
            return loadObservationsModule()

        case .person(let name):
            return loadPersonModule(name: name, isCollaboratorChat: isCollaboratorChat)

        case .location:
            return loadLocationModule()

        case .calendar:
            return loadCalendarModule()

        case .todayEpisode:
            return loadTodayEpisodeModule()
        }
    }

    // MARK: - Module Loaders

    private func loadCapabilitiesModule() -> String? {
        guard let capabilities = readFile("capabilities/inventory.md") else { return nil }
        let abbreviated = abbreviate(capabilities, maxLines: 100)
        return "## Capabilities\n\(abbreviated)"
    }

    private func loadDecisionsModule() -> String? {
        guard let decisions = readFile("memory/decisions.md") else { return nil }
        let truncated = lastLines(decisions, maxLines: maxLinesForLargeFiles)
        return "## Architectural Decisions\n\(truncated)"
    }

    private func loadLearningsModule() -> String? {
        guard let learnings = readFile("memory/learnings.md") else { return nil }
        let truncated = lastLines(learnings, maxLines: maxLinesForLargeFiles)
        return "## Learnings\n\(truncated)"
    }

    private func loadObservationsModule() -> String? {
        guard let observations = readFile("memory/observations.md") else { return nil }
        let truncated = lastLines(observations, maxLines: maxLinesForLargeFiles)
        return "## Self-Observations\n\(truncated)"
    }

    private func loadPersonModule(name: String, isCollaboratorChat: Bool) -> String? {
        let nameLower = name.lowercased()

        // Check if this is the collaborator - apply privacy rules
        let collaboratorLower = config.collaborator.name.lowercased()
        if nameLower == collaboratorLower || nameLower == "e" || nameLower == "é" {
            guard isCollaboratorChat else {
                return nil  // Don't load collaborator profile in non-collaborator chats
            }
        }

        // Try people/ structure first, then legacy
        let peoplePath = "memory/people/\(nameLower)/profile.md"
        let legacyPath = "memory/about-\(nameLower).md"

        if let profile = readFile(peoplePath) ?? readFile(legacyPath) {
            return "## About \(name)\n\(profile)"
        }

        return nil
    }

    private func loadLocationModule() -> String? {
        guard let locationSummary = buildLocationSummary() else { return nil }
        return "## Location Awareness\n\(locationSummary)"
    }

    private func loadCalendarModule() -> String? {
        // Use AppleScript to get today's calendar events
        let script = """
            tell application "Calendar"
                set today to current date
                set tomorrow to today + (1 * days)
                set eventList to ""

                repeat with cal in calendars
                    set calEvents to (every event of cal whose start date ≥ today and start date < tomorrow)
                    repeat with ev in calEvents
                        set eventList to eventList & "- " & (summary of ev) & " at " & time string of (start date of ev) & "\\n"
                    end repeat
                end repeat

                return eventList
            end tell
            """

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return "## Today's Calendar\n\(output)"
            }
        } catch {
            log("Failed to load calendar: \(error)", level: .warn, component: "MemoryContext")
        }

        return nil
    }

    private func loadTodayEpisodeModule() -> String? {
        let today = todayEpisodePath()
        guard let episode = readFile(today) else { return nil }
        let truncated = lastLines(episode, maxLines: maxLinesForEpisode)
        return "## Today's Activity\n\(truncated)"
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

    // MARK: - Hot Digest (Cross-Surface Context)

    /// Builds hot digest from unified event stream for cross-surface context
    /// Returns ~2-4K tokens of recent activity across ALL surfaces (iMessage, CLI, wake, etc.)
    /// This enables continuity: iMessage sessions know about CLI work, and vice versa
    ///
    /// - Parameter hours: Number of hours to look back (default 12)
    /// - Returns: Formatted markdown digest, or nil if unavailable
    func buildHotDigest(hours: Int = 12) -> String? {
        let scriptPath = (mindPath as NSString).appendingPathComponent("bin/build-hot-digest")

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            log("Hot digest script not found at \(scriptPath)", level: .debug, component: "MemoryContext")
            return nil
        }

        let process = Process()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        defer { try? outputHandle.close() }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "--hours", String(hours), "--no-ollama"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        // Set environment for the script
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        process.environment = env

        do {
            try process.run()

            // 5-second timeout to avoid blocking message responses
            let timeout: TimeInterval = 5
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                log("Hot digest timeout after \(Int(timeout))s - killing process", level: .warn, component: "MemoryContext")
                process.terminate()
                return nil
            }

            let data = outputHandle.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8),
                  !output.isEmpty,
                  !output.contains("No recent events") else {
                return nil
            }

            log("Hot digest loaded (\(output.count) chars)", level: .debug, component: "MemoryContext")
            return output
        } catch {
            log("Hot digest failed: \(error)", level: .warn, component: "MemoryContext")
            return nil
        }
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
    static var defaultIMessageInstructions: String {
        let sendImagePath = MindPaths.mindPath("bin/send-image")
        let lookPath = MindPaths.mindPath("bin/look")
        return """
        ## Response Instructions
        Your entire output will be sent as an iMessage. Respond naturally and concisely.
        - Keep responses brief (this is texting)
        - DO NOT narrate actions or use the message script
        - DO NOT use markdown formatting - Apple Messages displays it literally
        - To send images: \(sendImagePath) /path/to/file
        - To take photos: \(lookPath) -s
        """
    }

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
