import Foundation

enum MindPaths {
    static func mindPath(_ relativePath: String? = nil) -> String {
        mindURL(relativePath).path
    }

    static func mindURL(_ relativePath: String? = nil) -> URL {
        let base = mindDir
        guard let relativePath, !relativePath.isEmpty else {
            return base
        }
        return URL(fileURLWithPath: relativePath, relativeTo: base).standardizedFileURL
    }

    // MARK: - Domain Paths
    // Four-domain structure: self/, memory/, state/, system/

    /// Path to self/ domain (identity, goals, ritual, capabilities, credentials, media)
    static func selfPath(_ relativePath: String? = nil) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return mindPath("self")
        }
        return mindPath("self/\(relativePath)")
    }

    /// Path to memory/ domain (episodes, reflections, people, learnings, semantic, chroma, stream)
    static func memoryPath(_ relativePath: String? = nil) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return mindPath("memory")
        }
        return mindPath("memory/\(relativePath)")
    }

    /// Path to state/ domain (services, plans, handoffs, queues, location, etc.)
    static func statePath(_ relativePath: String? = nil) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return mindPath("state")
        }
        return mindPath("state/\(relativePath)")
    }

    /// Path to system/ domain (config, bin, lib, logs, senses, etc.)
    static func systemPath(_ relativePath: String? = nil) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return mindPath("system")
        }
        return mindPath("system/\(relativePath)")
    }

    static var mindDir: URL {
        if let override = resolveMindOverride() {
            return URL(fileURLWithPath: expandTilde(override)).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
    }

    private static func resolveMindOverride() -> String? {
        if let raw = getenv("SAMARA_MIND_PATH") {
            return String(cString: raw)
        }
        if let raw = getenv("MIND_PATH") {
            return String(cString: raw)
        }
        let env = ProcessInfo.processInfo.environment
        if let value = env["SAMARA_MIND_PATH"] ?? env["MIND_PATH"] {
            return value
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

/// Loads configuration from ~/.claude-mind/system/config.json
/// Falls back to hardcoded defaults if config is missing
struct Configuration: Codable {
    let entity: EntityConfig
    let collaborator: CollaboratorConfig
    let notes: NotesConfig
    let mail: MailConfig
    let models: ModelsConfig?
    let timeouts: TimeoutsConfig?
    let features: FeaturesConfig?
    let services: ServicesConfig?

    struct EntityConfig: Codable {
        let name: String
        let icloud: String
        let bluesky: String
        let x: String?
        let github: String
    }

    struct CollaboratorConfig: Codable {
        let name: String
        let phone: String
        let email: String
        let bluesky: String
        let x: String?
    }

    struct NotesConfig: Codable {
        let location: String
        let scratchpad: String
    }

    struct MailConfig: Codable {
        let account: String
    }

    /// Model configuration for multi-tier fallback
    struct ModelsConfig: Codable {
        let primary: String
        let fallbacks: [String]
        let localEndpoint: String
        let taskClassification: TaskClassificationConfig?

        struct TaskClassificationConfig: Codable {
            let simpleAck: [String]?
            let statusQuery: [String]?
            let complex: [String]?
        }

        static let defaults = ModelsConfig(
            primary: "claude",
            fallbacks: ["ollama:llama3.1:8b"],
            localEndpoint: "http://localhost:11434",
            taskClassification: nil
        )
    }

    /// Timeout configuration for various operations
    struct TimeoutsConfig: Codable {
        let claudeInvocation: Int
        let localModel: Int
        let stuckTask: Int

        static let defaults = TimeoutsConfig(
            claudeInvocation: 300,  // 5 minutes
            localModel: 60,         // 1 minute
            stuckTask: 7200         // 2 hours
        )
    }

    /// Feature flags for experimental functionality
    struct FeaturesConfig: Codable {
        /// Smart context loading: Uses Haiku to analyze messages and load only relevant context
        /// Reduces token usage from ~36K to ~5-10K per request (Phase: Smart Context)
        let smartContext: Bool?

        /// Context router timeout in seconds (how long to wait for Haiku classification)
        let smartContextTimeout: Double?

        static let defaults = FeaturesConfig(
            smartContext: true,        // Enabled by default
            smartContextTimeout: 5.0   // 5 second timeout for Haiku classification
        )
    }

    /// Service toggles for enabling/disabling sense handlers and watchers
    struct ServicesConfig: Codable {
        let x: Bool?
        let bluesky: Bool?
        let github: Bool?
        let wallet: Bool?
        let meeting: Bool?
        let webhook: Bool?
        let location: Bool?
        let browserHistory: Bool?
        let proactive: Bool?

        /// Check if a service is enabled (defaults to true if not specified)
        func isEnabled(_ service: String) -> Bool {
            switch service {
            case "x": return x ?? true
            case "bluesky": return bluesky ?? true
            case "github": return github ?? true
            case "wallet": return wallet ?? true
            case "meeting", "meeting_prep", "meeting_debrief": return meeting ?? true
            case "webhook": return webhook ?? true
            case "location": return location ?? true
            case "browserHistory", "browser_history": return browserHistory ?? true
            case "proactive": return proactive ?? true
            default: return true  // Unknown services default to enabled
            }
        }

        static let defaults = ServicesConfig(
            x: true,
            bluesky: true,
            github: true,
            wallet: true,
            meeting: true,
            webhook: true,
            location: true,
            browserHistory: true,
            proactive: true
        )
    }

    /// Default configuration (fallback if config.json doesn't exist)
    /// NOTE: These are empty templates - all values should come from config.json
    static let defaults = Configuration(
        entity: EntityConfig(
            name: "Claude",
            icloud: "",
            bluesky: "",
            x: "",
            github: ""
        ),
        collaborator: CollaboratorConfig(
            name: "",
            phone: "",
            email: "",
            bluesky: "",
            x: ""
        ),
        notes: NotesConfig(
            location: "Claude Location Log",
            scratchpad: "Claude Scratchpad"
        ),
        mail: MailConfig(
            account: "iCloud"
        ),
        models: nil,
        timeouts: nil,
        features: nil,
        services: nil
    )

    /// Convenience accessors with defaults
    var modelsConfig: ModelsConfig {
        models ?? ModelsConfig.defaults
    }

    var timeoutsConfig: TimeoutsConfig {
        timeouts ?? TimeoutsConfig.defaults
    }

    var featuresConfig: FeaturesConfig {
        features ?? FeaturesConfig.defaults
    }

    var servicesConfig: ServicesConfig {
        services ?? ServicesConfig.defaults
    }

    /// Load configuration from ~/.claude-mind/system/config.json
    /// Returns defaults if file doesn't exist or can't be parsed
    static func load() -> Configuration {
        let configPath = MindPaths.mindURL("system/config.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            log("config.json not found, using defaults", level: .info, component: "Configuration")
            return defaults
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(Configuration.self, from: data)
            log("Loaded from config.json", level: .info, component: "Configuration")
            log("Entity: \(config.entity.name)", level: .info, component: "Configuration")
            log("Collaborator: \(config.collaborator.name)", level: .info, component: "Configuration")
            return config
        } catch {
            log("Failed to parse config.json: \(error)", level: .warn, component: "Configuration")
            log("Using defaults", level: .info, component: "Configuration")
            return defaults
        }
    }
}

// Global configuration instance
let config = Configuration.load()
