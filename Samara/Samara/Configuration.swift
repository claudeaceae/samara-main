import Foundation

/// Loads configuration from ~/.claude-mind/config.json
/// Falls back to hardcoded defaults if config is missing
struct Configuration: Codable {
    let entity: EntityConfig
    let collaborator: CollaboratorConfig
    let notes: NotesConfig
    let mail: MailConfig

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
        )
    )

    /// Load configuration from ~/.claude-mind/config.json
    /// Returns defaults if file doesn't exist or can't be parsed
    static func load() -> Configuration {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind/config.json")

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
