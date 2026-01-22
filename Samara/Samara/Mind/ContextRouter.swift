import Foundation

/// Determines what context modules are needed based on message content
/// Uses Haiku for smart classification (~500ms latency)
final class ContextRouter {

    // MARK: - Types

    /// Context modules that can be loaded on-demand
    enum ContextModule: Hashable {
        case capabilities
        case decisions
        case learnings
        case observations
        case person(String)  // Person name
        case location
        case calendar
        case todayEpisode
    }

    /// Results of message analysis - what context is needed
    struct ContextNeeds {
        var needsCapabilities: Bool = false
        var needsDecisions: Bool = false
        var needsLearnings: Bool = false
        var needsObservations: Bool = false
        var needsPersonProfiles: [String] = []
        var needsLocationContext: Bool = false
        var needsCalendarContext: Bool = false
        var needsTodayEpisode: Bool = true  // Usually needed for continuity
        var searchQueries: [String] = []
        var isSimpleGreeting: Bool = false

        /// Convert to list of required modules
        var requiredModules: [ContextModule] {
            var modules: [ContextModule] = []

            if needsCapabilities { modules.append(.capabilities) }
            if needsDecisions { modules.append(.decisions) }
            if needsLearnings { modules.append(.learnings) }
            if needsObservations { modules.append(.observations) }
            if needsLocationContext { modules.append(.location) }
            if needsCalendarContext { modules.append(.calendar) }
            if needsTodayEpisode { modules.append(.todayEpisode) }

            for person in needsPersonProfiles {
                modules.append(.person(person))
            }

            return modules
        }

        /// Estimated token count for these needs
        var estimatedTokens: Int {
            var tokens = 3200  // Core context always loaded

            if needsCapabilities { tokens += 1200 }
            if needsDecisions { tokens += 700 }
            if needsLearnings { tokens += 700 }
            if needsObservations { tokens += 700 }
            if needsLocationContext { tokens += 250 }
            if needsCalendarContext { tokens += 400 }
            if needsTodayEpisode { tokens += 900 }

            tokens += needsPersonProfiles.count * 450
            tokens += searchQueries.count * 250

            return tokens
        }
    }

    /// Haiku classification response structure
    private struct Classification: Decodable {
        let isActionRelated: Bool
        let referencesHistory: Bool
        let mentionedPeople: [String]
        let isLocationRelated: Bool
        let isScheduleRelated: Bool
        let searchTerms: [String]
        let isSimpleGreeting: Bool
        let needsRecentContext: Bool
        let needsLearnings: Bool
        let needsObservations: Bool

        private enum CodingKeys: String, CodingKey {
            case isActionRelated
            case referencesHistory
            case mentionedPeople
            case isLocationRelated
            case isScheduleRelated
            case searchTerms
            case isSimpleGreeting
            case needsRecentContext
            case needsLearnings
            case needsObservations
        }

        init(
            isActionRelated: Bool,
            referencesHistory: Bool,
            mentionedPeople: [String],
            isLocationRelated: Bool,
            isScheduleRelated: Bool,
            searchTerms: [String],
            isSimpleGreeting: Bool,
            needsRecentContext: Bool,
            needsLearnings: Bool,
            needsObservations: Bool
        ) {
            self.isActionRelated = isActionRelated
            self.referencesHistory = referencesHistory
            self.mentionedPeople = mentionedPeople
            self.isLocationRelated = isLocationRelated
            self.isScheduleRelated = isScheduleRelated
            self.searchTerms = searchTerms
            self.isSimpleGreeting = isSimpleGreeting
            self.needsRecentContext = needsRecentContext
            self.needsLearnings = needsLearnings
            self.needsObservations = needsObservations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isActionRelated = try container.decodeIfPresent(Bool.self, forKey: .isActionRelated) ?? false
            referencesHistory = try container.decodeIfPresent(Bool.self, forKey: .referencesHistory) ?? false
            mentionedPeople = try container.decodeIfPresent([String].self, forKey: .mentionedPeople) ?? []
            isLocationRelated = try container.decodeIfPresent(Bool.self, forKey: .isLocationRelated) ?? false
            isScheduleRelated = try container.decodeIfPresent(Bool.self, forKey: .isScheduleRelated) ?? false
            searchTerms = try container.decodeIfPresent([String].self, forKey: .searchTerms) ?? []
            isSimpleGreeting = try container.decodeIfPresent(Bool.self, forKey: .isSimpleGreeting) ?? false
            needsRecentContext = try container.decodeIfPresent(Bool.self, forKey: .needsRecentContext) ?? true
            needsLearnings = try container.decodeIfPresent(Bool.self, forKey: .needsLearnings) ?? false
            needsObservations = try container.decodeIfPresent(Bool.self, forKey: .needsObservations) ?? false
        }

        // Default values for fallback
        static var fallback: Classification {
            Classification(
                isActionRelated: false,
                referencesHistory: false,
                mentionedPeople: [],
                isLocationRelated: false,
                isScheduleRelated: false,
                searchTerms: [],
                isSimpleGreeting: false,
                needsRecentContext: true,
                needsLearnings: false,
                needsObservations: false
            )
        }
    }

    private static let classificationKeys: Set<String> = [
        "isActionRelated",
        "referencesHistory",
        "mentionedPeople",
        "isLocationRelated",
        "isScheduleRelated",
        "searchTerms",
        "isSimpleGreeting",
        "needsRecentContext",
        "needsLearnings",
        "needsObservations"
    ]

    // MARK: - Properties

    private let claudePath: String
    private let timeout: TimeInterval
    private let enabled: Bool
    private let outputProvider: ((String) -> String?)?

    // MARK: - Initialization

    init(
        claudePath: String = "/usr/local/bin/claude",
        timeout: TimeInterval = 5.0,
        enabled: Bool = true,
        outputProvider: ((String) -> String?)? = nil
    ) {
        self.claudePath = claudePath
        self.timeout = timeout
        self.enabled = enabled
        self.outputProvider = outputProvider
    }

    // MARK: - Public Methods

    /// Analyze messages to determine what context is needed
    /// - Parameter messages: Array of incoming messages
    /// - Returns: ContextNeeds indicating required modules
    func analyze(_ messages: [Message]) -> ContextNeeds {
        guard enabled else {
            // Feature disabled - return full context needs (fallback behavior)
            return fullContextNeeds()
        }

        let combinedText = messages.map { $0.fullDescription }.joined(separator: "\n")

        // Try Haiku classification
        if let classification = classifyWithHaiku(combinedText) {
            return convertToNeeds(classification)
        }

        // Fallback: Use simple keyword analysis
        log("Haiku classification failed, using keyword fallback", level: .warn, component: "ContextRouter")
        return analyzeWithKeywords(combinedText)
    }

    /// Analyze a sense event to determine context needs
    /// - Parameter event: The sense event to analyze
    /// - Returns: ContextNeeds for the event
    func analyzeEvent(_ event: SenseEvent) -> ContextNeeds {
        guard enabled else {
            return fullContextNeeds()
        }

        // Extract text from event for analysis
        var eventText = "Event type: \(event.sense)\n"

        if let suggestedPrompt = event.context?.suggestedPrompt {
            eventText += suggestedPrompt
        }

        // Add any text content from event data
        if let text = event.getString("text") {
            eventText += "\n" + text
        }

        if let classification = classifyWithHaiku(eventText) {
            return convertToNeeds(classification)
        }

        // Fallback for sense events: minimal context
        return minimalContextNeeds(for: event)
    }

    // MARK: - Private Methods

    /// Call Haiku to classify the message
    private func classifyWithHaiku(_ text: String) -> Classification? {
        if let outputProvider = outputProvider {
            guard let output = outputProvider(text), !output.isEmpty else {
                return nil
            }
            return parseClassification(output)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Find claude executable
        let possiblePaths = [
            claudePath,
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude"
        ]

        guard let executablePath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            log("Claude CLI not found", level: .error, component: "ContextRouter")
            return nil
        }

        process.executableURL = URL(fileURLWithPath: executablePath)

        // Build the classification prompt
        let prompt = buildClassificationPrompt(for: text)

        // Use Haiku with print mode for quick classification
        process.arguments = [
            "-p", prompt,
            "--model", "haiku",
            "--output-format", "json",
            "--max-turns", "1"
        ]

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        process.environment = env

        do {
            try process.run()

            // Wait with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                log("Haiku classification timed out after \(timeout)s", level: .warn, component: "ContextRouter")
                process.terminate()
                return nil
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
                return nil
            }

            // Parse the JSON response
            return parseClassification(output)

        } catch {
            log("Haiku classification error: \(error)", level: .error, component: "ContextRouter")
            return nil
        }
    }

    /// Build the prompt for Haiku classification
    private func buildClassificationPrompt(for text: String) -> String {
        return """
            Analyze this message and determine what context is needed to respond well.

            MESSAGE:
            \(text)

            Return a JSON object with these fields:
            {
              "isActionRelated": boolean,      // Asking about capabilities, how to do something
              "referencesHistory": boolean,    // Mentions past decisions, "remember when", "why did we"
              "mentionedPeople": string[],     // Names of specific people mentioned
              "isLocationRelated": boolean,    // Where questions, place references
              "isScheduleRelated": boolean,    // Calendar, meeting, schedule mentions
              "searchTerms": string[],         // Key concepts to search memory for (max 5)
              "isSimpleGreeting": boolean,     // Just hi/thanks/ok with no real question
              "needsRecentContext": boolean,   // Needs recent conversation context
              "needsLearnings": boolean,       // Needs learnings/insights context
              "needsObservations": boolean     // Needs observations/patterns context
            }

            Return ONLY the JSON object, no other text.
            """
    }

    /// Parse Haiku's classification response
    private func parseClassification(_ output: String) -> Classification? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let parsed = decodeClassification(from: json) {
            return parsed
        }

        if let parsed = decodeClassification(from: trimmed) {
            return parsed
        }

        log("Failed to parse classification output", level: .warn, component: "ContextRouter")
        return nil
    }

    private func decodeClassification(from dict: [String: Any]) -> Classification? {
        let keys = Set(dict.keys)
        guard !keys.isDisjoint(with: Self.classificationKeys) else {
            return nil
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let decoded = try? JSONDecoder().decode(Classification.self, from: data) {
            return decoded
        }

        return Classification(
            isActionRelated: boolValue(dict["isActionRelated"]),
            referencesHistory: boolValue(dict["referencesHistory"]),
            mentionedPeople: stringArray(from: dict["mentionedPeople"]),
            isLocationRelated: boolValue(dict["isLocationRelated"]),
            isScheduleRelated: boolValue(dict["isScheduleRelated"]),
            searchTerms: stringArray(from: dict["searchTerms"]),
            isSimpleGreeting: boolValue(dict["isSimpleGreeting"]),
            needsRecentContext: boolValue(dict["needsRecentContext"], defaultValue: true),
            needsLearnings: boolValue(dict["needsLearnings"]),
            needsObservations: boolValue(dict["needsObservations"])
        )
    }

    private func decodeClassification(from jsonString: String) -> Classification? {
        var trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        if let jsonStart = trimmed.firstIndex(of: "{"),
           let jsonEnd = trimmed.lastIndex(of: "}") {
            trimmed = String(trimmed[jsonStart...jsonEnd])
        }

        guard let data = trimmed.data(using: .utf8) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return decodeClassification(from: json)
    }

    private func decodeClassification(from value: Any) -> Classification? {
        if let dict = value as? [String: Any] {
            if let parsed = decodeClassification(from: dict) {
                return parsed
            }

            if let structured = dict["structured_output"] {
                if let parsed = decodeClassification(from: structured) {
                    return parsed
                }
            }

            if let result = dict["result"] {
                if let parsed = decodeClassification(from: result) {
                    return parsed
                }
            }

            return nil
        }

        if let stringValue = value as? String {
            return decodeClassification(from: stringValue)
        }

        return nil
    }

    private func boolValue(_ value: Any?, defaultValue: Bool = false) -> Bool {
        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = value as? String {
            return (stringValue as NSString).boolValue
        }

        return defaultValue
    }

    private func stringArray(from value: Any?) -> [String] {
        if let arrayValue = value as? [String] {
            return arrayValue
        }

        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }

        if let stringValue = value as? String {
            return [stringValue]
        }

        return []
    }

    /// Convert Haiku's classification to ContextNeeds
    private func convertToNeeds(_ classification: Classification) -> ContextNeeds {
        var needs = ContextNeeds()

        needs.needsCapabilities = classification.isActionRelated
        needs.needsDecisions = classification.referencesHistory
        needs.needsPersonProfiles = classification.mentionedPeople
        needs.needsLocationContext = classification.isLocationRelated
        needs.needsCalendarContext = classification.isScheduleRelated
        needs.searchQueries = classification.searchTerms
        needs.isSimpleGreeting = classification.isSimpleGreeting
        needs.needsTodayEpisode = classification.needsRecentContext
        needs.needsLearnings = classification.needsLearnings
        needs.needsObservations = classification.needsObservations

        // Simple greetings need minimal context
        if classification.isSimpleGreeting {
            needs.needsTodayEpisode = false
            needs.needsLearnings = false
            needs.needsObservations = false
        }

        log("Context needs: \(needs.estimatedTokens) tokens, modules: \(needs.requiredModules.count)",
            level: .debug, component: "ContextRouter")

        return needs
    }

    /// Keyword-based fallback analysis
    private func analyzeWithKeywords(_ text: String) -> ContextNeeds {
        var needs = ContextNeeds()
        let lowercased = text.lowercased()

        // Capability signals
        let capabilitySignals = ["can you", "are you able", "how do i", "how to", "is it possible"]
        needs.needsCapabilities = capabilitySignals.contains { lowercased.contains($0) }

        // History signals
        let historySignals = ["remember when", "why did we", "last time", "previously", "before"]
        needs.needsDecisions = historySignals.contains { lowercased.contains($0) }

        // Location signals
        let locationSignals = ["where", "location", "home", "work", "place", "address"]
        needs.needsLocationContext = locationSignals.contains { lowercased.contains($0) }

        // Calendar signals
        let calendarSignals = ["schedule", "meeting", "calendar", "appointment", "event"]
        needs.needsCalendarContext = calendarSignals.contains { lowercased.contains($0) }

        // Learnings/insights signals
        let learningSignals = ["learned", "learning", "learnings", "lesson", "takeaway", "insight"]
        needs.needsLearnings = learningSignals.contains { lowercased.contains($0) }

        // Observations/patterns signals
        let observationSignals = ["observation", "observations", "pattern", "patterns", "noticed", "trend"]
        needs.needsObservations = observationSignals.contains { lowercased.contains($0) }

        // Simple greeting detection
        let greetingPatterns = ["^hi$", "^hey$", "^hello$", "^thanks$", "^ok$", "^okay$", "^cool$"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        needs.isSimpleGreeting = greetingPatterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }

        // Extract search terms
        needs.searchQueries = extractSearchTerms(from: text)

        return needs
    }

    /// Extract meaningful search terms from text
    private func extractSearchTerms(from text: String) -> [String] {
        let stopWords = Set(["a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
                             "have", "has", "had", "do", "does", "did", "will", "would", "could",
                             "should", "may", "might", "must", "shall", "can", "to", "of", "in",
                             "for", "on", "with", "at", "by", "from", "as", "or", "and", "but",
                             "if", "then", "so", "than", "that", "this", "these", "those", "it",
                             "its", "my", "your", "his", "her", "their", "our", "me", "you", "him",
                             "her", "them", "us", "what", "which", "who", "whom", "whose", "where",
                             "when", "why", "how", "i", "we", "he", "she", "they", "just", "very",
                             "really", "actually", "basically", "literally", "probably", "maybe"])

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        return Array(Set(words)).prefix(5).map { String($0) }
    }

    /// Return full context needs (fallback when routing disabled)
    private func fullContextNeeds() -> ContextNeeds {
        var needs = ContextNeeds()
        needs.needsCapabilities = true
        needs.needsDecisions = true
        needs.needsLearnings = true
        needs.needsObservations = true
        needs.needsLocationContext = true
        needs.needsCalendarContext = false
        needs.needsTodayEpisode = true
        return needs
    }

    /// Minimal context needs for sense events
    private func minimalContextNeeds(for event: SenseEvent) -> ContextNeeds {
        var needs = ContextNeeds()

        switch event.sense {
        case "x", "bluesky", "github":
            // Social media: minimal context, search for related
            needs.needsCapabilities = true
            needs.needsTodayEpisode = false
        case "wallet":
            // Wallet: very minimal
            needs.needsTodayEpisode = false
        case "meeting_prep", "meeting_debrief":
            // Meetings: need calendar and person context
            needs.needsCalendarContext = true
            if let attendees = event.getArray("attendees") as? [[String: Any]] {
                needs.needsPersonProfiles = attendees.compactMap { $0["name"] as? String }
            }
        default:
            // Other events: moderate context
            needs.needsTodayEpisode = true
        }

        return needs
    }
}
