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

    static var mindDir: URL {
        if let override = resolveMindOverride() {
            return URL(fileURLWithPath: expandTilde(override)).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
    }

    private static func resolveMindOverride() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env["SAMARA_MIND_PATH"] ?? env["MIND_PATH"] {
            return value
        }
        if let raw = getenv("SAMARA_MIND_PATH") {
            return String(cString: raw)
        }
        if let raw = getenv("MIND_PATH") {
            return String(cString: raw)
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

/// Loads configuration from ~/.claude-mind/config.json
/// Falls back to hardcoded defaults if config is missing
struct Configuration: Codable {
    let entity: EntityConfig
    let collaborator: CollaboratorConfig
    let notes: NotesConfig
    let mail: MailConfig
    let models: ModelsConfig?
    let timeouts: TimeoutsConfig?

    struct EntityConfig: Codable {
        let name: String
        let icloud: String
        let bluesky: String
        let github: String
    }

    struct CollaboratorConfig: Codable {
        let name: String
        let phone: String
        let email: String
        let bluesky: String
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

    /// Default configuration (fallback if config.json doesn't exist)
    static let defaults = Configuration(
        entity: EntityConfig(
            name: "Claude",
            icloud: "claudeaceae@icloud.com",
            bluesky: "@claudaceae.bsky.social",
            github: "claudeaceae"
        ),
        collaborator: CollaboratorConfig(
            name: "É",
            phone: "+15206099095",
            email: "edouard@urcad.es",
            bluesky: "@urcad.es"
        ),
        notes: NotesConfig(
            location: "Claude Location Log",
            scratchpad: "Claude Scratchpad"
        ),
        mail: MailConfig(
            account: "iCloud"
        ),
        models: nil,
        timeouts: nil
    )

    /// Convenience accessors with defaults
    var modelsConfig: ModelsConfig {
        models ?? ModelsConfig.defaults
    }

    var timeoutsConfig: TimeoutsConfig {
        timeouts ?? TimeoutsConfig.defaults
    }

    /// Load configuration from ~/.claude-mind/config.json
    /// Returns defaults if file doesn't exist or can't be parsed
    static func load() -> Configuration {
        let configPath = MindPaths.mindURL("config.json")

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
