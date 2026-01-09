import Foundation

/// Represents an event from a satellite sense service
/// All satellites write events in this canonical format to ~/.claude-mind/senses/
struct SenseEvent: Codable {
    /// Unique sense identifier (e.g., "location", "webhook", "feed")
    let sense: String

    /// When the event occurred
    let timestamp: Date

    /// How urgently Claude should process this
    let priority: Priority

    /// Sense-specific payload
    let data: [String: AnyCodable]

    /// Optional context hints for Claude
    let context: Context?

    /// Optional authentication for non-Tailscale sources
    let auth: Auth?

    // MARK: - Nested Types

    enum Priority: String, Codable {
        case immediate    // Process right away, interrupt if needed
        case normal       // Process in normal queue
        case background   // Process during idle time
    }

    struct Context: Codable {
        /// Optional prompt hint for Claude
        let suggestedPrompt: String?

        /// Paths to related files Claude should read
        let relatedFiles: [String]?

        /// If true, process but don't message collaborator
        let suppressResponse: Bool?

        enum CodingKeys: String, CodingKey {
            case suggestedPrompt = "suggested_prompt"
            case relatedFiles = "related_files"
            case suppressResponse = "suppress_response"
        }
    }

    struct Auth: Codable {
        /// Verified satellite identifier
        let sourceId: String?

        /// HMAC signature if using shared secrets
        let signature: String?

        enum CodingKeys: String, CodingKey {
            case sourceId = "source_id"
            case signature
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case sense, timestamp, priority, data, context, auth
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sense = try container.decode(String.self, forKey: .sense)

        // Parse timestamp - support ISO8601 with and without fractional seconds
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestampString) {
            timestamp = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: timestampString) {
                timestamp = date
            } else {
                throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Invalid timestamp format")
            }
        }

        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .data) ?? [:]
        context = try container.decodeIfPresent(Context.self, forKey: .context)
        auth = try container.decodeIfPresent(Auth.self, forKey: .auth)
    }

    // MARK: - Initialization

    init(
        sense: String,
        timestamp: Date = Date(),
        priority: Priority = .normal,
        data: [String: AnyCodable] = [:],
        context: Context? = nil,
        auth: Auth? = nil
    ) {
        self.sense = sense
        self.timestamp = timestamp
        self.priority = priority
        self.data = data
        self.context = context
        self.auth = auth
    }
}

// MARK: - AnyCodable for flexible data payload

/// Type-erased Codable wrapper for arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Convenience accessors for data payload

extension SenseEvent {
    /// Get a string value from the data payload
    func getString(_ key: String) -> String? {
        return data[key]?.value as? String
    }

    /// Get a double value from the data payload
    func getDouble(_ key: String) -> Double? {
        return data[key]?.value as? Double
    }

    /// Get an int value from the data payload
    func getInt(_ key: String) -> Int? {
        return data[key]?.value as? Int
    }

    /// Get a bool value from the data payload
    func getBool(_ key: String) -> Bool? {
        return data[key]?.value as? Bool
    }

    /// Get an array value from the data payload
    func getArray(_ key: String) -> [Any]? {
        return data[key]?.value as? [Any]
    }

    /// Get a dict value from the data payload
    func getDict(_ key: String) -> [String: Any]? {
        return data[key]?.value as? [String: Any]
    }
}

// MARK: - Debug description

extension SenseEvent: CustomStringConvertible {
    var description: String {
        let formatter = ISO8601DateFormatter()
        return "SenseEvent(sense: \(sense), timestamp: \(formatter.string(from: timestamp)), priority: \(priority.rawValue))"
    }
}
