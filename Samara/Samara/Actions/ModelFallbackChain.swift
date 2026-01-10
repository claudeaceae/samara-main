import Foundation

/// Task complexity levels for routing to appropriate models
enum TaskComplexity {
    case simpleAck      // "Got it", "Thanks", basic acknowledgments
    case statusQuery    // "What time is it?", "Where am I?", status checks
    case complex        // Everything else requiring full Claude capabilities
}

/// Model tiers in order of preference (lowest = most preferred)
enum ModelTier: Int, Comparable, CaseIterable {
    case claudePrimary = 0    // Primary Claude API
    case claudeFallback = 1   // Retry Claude (possibly different params)
    case localOllama = 2      // Local Ollama model
    case queued = 3           // All tiers exhausted, queue for later

    static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .claudePrimary: return "claudePrimary"
        case .claudeFallback: return "claudeFallback"
        case .localOllama: return "localOllama"
        case .queued: return "queued"
        }
    }
}

/// Errors during fallback chain execution
enum FallbackChainError: Error, CustomStringConvertible {
    case allTiersFailed([Error])
    case invalidConfiguration(String)

    var description: String {
        switch self {
        case .allTiersFailed(let errors):
            let errorDescs = errors.map { String(describing: $0) }.joined(separator: "; ")
            return "All model tiers failed: \(errorDescs)"
        case .invalidConfiguration(let msg):
            return "Invalid fallback configuration: \(msg)"
        }
    }
}

/// Result from the fallback chain execution
struct FallbackChainResult {
    let response: String
    let tier: ModelTier
    let sessionId: String?

    /// Whether this was handled by a local model (no Claude API used)
    var usedLocalModel: Bool {
        tier == .localOllama
    }
}

/// Orchestrates model invocation with intelligent fallback
/// Routes simple tasks to local models, falls back on API errors
final class ModelFallbackChain {

    // MARK: - Properties

    private let config: Configuration.ModelsConfig
    private let localInvoker: LocalModelInvoker
    private let timeoutConfig: Configuration.TimeoutsConfig

    // MARK: - Task Classification Patterns

    /// Patterns indicating simple acknowledgment tasks
    private let ackPatterns: [String] = [
        "^(ok|okay|sure|thanks|thank you|got it|sounds good|perfect|great|cool|nice|yep|yes|no|alright|understood)$",
        "^(👍|👌|✅|❤️|🙏|😊|🎉|💯)$",
        "^(k|kk|ty|thx|np|yw)$"
    ]

    /// Patterns indicating status queries
    private let statusPatterns: [String] = [
        "\\b(what time|what's the time|current time)\\b",
        "\\b(where am i|what's my location|my location|current location)\\b",
        "\\b(what day|what date|today's date|current date)\\b",
        "\\b(weather|temperature|forecast)\\b",
        "\\b(battery|disk space|memory usage|system status)\\b"
    ]

    /// Patterns indicating complex tasks requiring full Claude capabilities
    private let complexPatterns: [String] = [
        "\\b(write|code|implement|create|build|develop|design)\\b",
        "\\b(analyze|explain|summarize|compare|evaluate)\\b",
        "\\b(fix|debug|troubleshoot|investigate|diagnose)\\b",
        "\\b(plan|strategy|approach|architecture)\\b",
        "\\b(search|find|look up|research)\\b",
        "\\b(read|check|review|examine).*file\\b",
        "\\b(send|post|message|email|notify)\\b",
        "\\b(calendar|schedule|meeting|appointment)\\b"
    ]

    // MARK: - Initialization

    init(config: Configuration.ModelsConfig, localInvoker: LocalModelInvoker, timeoutConfig: Configuration.TimeoutsConfig? = nil) {
        self.config = config
        self.localInvoker = localInvoker
        self.timeoutConfig = timeoutConfig ?? .defaults
    }

    // MARK: - Task Classification

    /// Classify task complexity based on prompt content
    func classifyTask(_ prompt: String) -> TaskComplexity {
        let lowered = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Very short messages are likely acknowledgments
        if lowered.count < 20 {
            for pattern in ackPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   regex.firstMatch(in: lowered, options: [], range: NSRange(lowered.startIndex..., in: lowered)) != nil {
                    return .simpleAck
                }
            }
        }

        // Check for complex task indicators first (higher priority)
        for pattern in complexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: lowered, options: [], range: NSRange(lowered.startIndex..., in: lowered)) != nil {
                return .complex
            }
        }

        // Check for status query patterns
        for pattern in statusPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: lowered, options: [], range: NSRange(lowered.startIndex..., in: lowered)) != nil {
                return .statusQuery
            }
        }

        // Default to complex for safety (use Claude for unknown cases)
        return .complex
    }

    /// Determine the starting tier based on task complexity and availability
    func startingTier(for complexity: TaskComplexity) -> ModelTier {
        switch complexity {
        case .simpleAck:
            // Simple acknowledgments can start at local tier if available
            return .localOllama

        case .statusQuery:
            // Status queries can often be handled locally with context injection
            return .localOllama

        case .complex:
            // Complex tasks always start with Claude
            return .claudePrimary
        }
    }

    // MARK: - Error Classification

    /// Determine if we should fall back to local model for this error
    func shouldFallbackToLocal(_ error: Error) -> Bool {
        let errorDesc = String(describing: error).lowercased()

        // Network errors → try local
        if errorDesc.contains("network") || errorDesc.contains("nsurlerror") || errorDesc.contains("connection") {
            return true
        }

        // Rate limiting → try local
        if errorDesc.contains("rate") || errorDesc.contains("429") || errorDesc.contains("quota") {
            return true
        }

        // Timeout → try local (local might be faster)
        if errorDesc.contains("timeout") || errorDesc.contains("timed out") {
            return true
        }

        // Service unavailable → try local
        if errorDesc.contains("unavailable") || errorDesc.contains("503") || errorDesc.contains("502") {
            return true
        }

        // Auth errors → don't try local (config issue)
        if errorDesc.contains("auth") || errorDesc.contains("401") || errorDesc.contains("403") {
            return false
        }

        // Context overflow → don't try local (local won't help)
        if errorDesc.contains("context") || errorDesc.contains("too long") || errorDesc.contains("overflow") {
            return false
        }

        // Default: try local as fallback
        return true
    }

    // MARK: - Execution

    /// Execute invocation with fallback chain
    /// - Parameters:
    ///   - prompt: The prompt to send
    ///   - sessionId: Optional session ID for Claude resumption
    ///   - context: Context data for status queries (time, location, etc.)
    ///   - primaryInvoker: Closure that invokes Claude CLI
    /// - Returns: FallbackChainResult with response and tier used
    func execute(
        prompt: String,
        sessionId: String?,
        context: String = "",
        primaryInvoker: @escaping (String, String?) async throws -> ClaudeInvocationResult
    ) async throws -> FallbackChainResult {
        var errors: [Error] = []
        let complexity = classifyTask(prompt)
        var currentTier = startingTier(for: complexity)

        log("Task classified as '\(complexity)', starting at tier '\(currentTier.description)'",
            level: .info, component: "FallbackChain")

        while currentTier < .queued {
            do {
                switch currentTier {
                case .claudePrimary, .claudeFallback:
                    log("Trying tier: \(currentTier.description)", level: .info, component: "FallbackChain")
                    let result = try await primaryInvoker(prompt, sessionId)
                    log("Success from tier: \(currentTier.description)", level: .info, component: "FallbackChain")
                    return FallbackChainResult(
                        response: result.response,
                        tier: currentTier,
                        sessionId: result.sessionId
                    )

                case .localOllama:
                    log("Trying tier: localOllama", level: .info, component: "FallbackChain")

                    // Check if Ollama is available
                    guard await localInvoker.isAvailable() else {
                        log("Ollama not available, skipping local tier", level: .warn, component: "FallbackChain")
                        throw LocalModelError.serviceUnavailable
                    }

                    // Extract model name from config fallbacks
                    let modelName = extractOllamaModel()

                    // Route based on task complexity
                    let response: String
                    switch complexity {
                    case .simpleAck:
                        response = try await localInvoker.invokeSimpleAck(model: modelName, context: prompt)

                    case .statusQuery:
                        response = try await localInvoker.invokeStatusQuery(
                            model: modelName,
                            query: prompt,
                            contextData: context
                        )

                    case .complex:
                        // Complex tasks at local tier - this is a fallback, not ideal
                        log("Complex task falling back to local model - limited capability",
                            level: .warn, component: "FallbackChain")
                        response = try await localInvoker.invoke(model: modelName, prompt: prompt)
                    }

                    log("Success from tier: localOllama", level: .info, component: "FallbackChain")
                    return FallbackChainResult(
                        response: response,
                        tier: .localOllama,
                        sessionId: nil  // No session for local models
                    )

                case .queued:
                    // Should not reach here in the loop
                    break
                }
            } catch {
                log("Tier '\(currentTier.description)' failed: \(error)", level: .warn, component: "FallbackChain")
                errors.append(error)

                // Determine next tier
                if let nextTier = ModelTier(rawValue: currentTier.rawValue + 1) {
                    // Special handling: Skip local if it won't help with this error
                    if nextTier == .localOllama && !shouldFallbackToLocal(error) {
                        log("Skipping local tier (error type won't benefit from fallback)",
                            level: .info, component: "FallbackChain")
                        currentTier = .queued
                    } else {
                        currentTier = nextTier
                    }
                } else {
                    currentTier = .queued
                }
            }
        }

        // All tiers exhausted
        log("All model tiers exhausted after \(errors.count) failures", level: .error, component: "FallbackChain")
        throw FallbackChainError.allTiersFailed(errors)
    }

    // MARK: - Helpers

    /// Extract Ollama model name from config fallbacks
    private func extractOllamaModel() -> String {
        // Look for "ollama:modelname" pattern in fallbacks
        for fallback in config.fallbacks {
            if fallback.hasPrefix("ollama:") {
                return String(fallback.dropFirst("ollama:".count))
            }
        }
        // Default model
        return "llama3.1:8b"
    }
}
