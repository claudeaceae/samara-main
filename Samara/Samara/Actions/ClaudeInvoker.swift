import Foundation

/// Result of a Claude invocation
struct ClaudeInvocationResult {
    let response: String
    let sessionId: String?
}

/// Invokes the Claude Code CLI to process messages
final class ClaudeInvoker {
    /// Path to the claude CLI
    private let claudePath: String

    /// Timeout for Claude invocations
    private let timeout: TimeInterval

    /// Memory context for related memories search
    private let memoryContext: MemoryContext

    /// Resolves phone numbers/emails to contact names
    private let contactsResolver = ContactsResolver()

    /// Maximum retry attempts for session-related errors
    private let maxRetries = 2

    /// Local model invoker for Ollama fallback
    private let localInvoker: LocalModelInvoker

    /// Fallback chain for multi-tier model invocation
    private let fallbackChain: ModelFallbackChain

    /// Whether to use fallback chain (can be disabled for testing)
    private let useFallbackChain: Bool

    /// Tracks context window usage and provides tiered warnings
    private let contextTracker: ContextTracker

    /// Manages session ledgers for structured handoffs
    private let ledgerManager: LedgerManager

    init(claudePath: String = "/usr/local/bin/claude", timeout: TimeInterval = 300, memoryContext: MemoryContext? = nil, useFallbackChain: Bool = true) {
        self.claudePath = claudePath
        self.timeout = timeout
        self.memoryContext = memoryContext ?? MemoryContext()
        self.useFallbackChain = useFallbackChain

        // Initialize local model invoker with config
        let localEndpoint = URL(string: config.modelsConfig.localEndpoint) ?? URL(string: "http://localhost:11434")!
        let localTimeout = TimeInterval(config.timeoutsConfig.localModel)
        self.localInvoker = LocalModelInvoker(endpoint: localEndpoint, timeout: localTimeout)

        // Initialize fallback chain
        self.fallbackChain = ModelFallbackChain(
            config: config.modelsConfig,
            localInvoker: self.localInvoker,
            timeoutConfig: config.timeoutsConfig
        )

        // Initialize context tracking (200K tokens for Claude 4)
        self.contextTracker = ContextTracker(maxTokens: 200_000)

        // Initialize ledger manager
        self.ledgerManager = LedgerManager()

        log("ClaudeInvoker initialized (fallback=\(useFallbackChain), localEndpoint=\(localEndpoint))",
            level: .info, component: "ClaudeInvoker")
    }

    /// Invokes Claude with a batch of messages and optional session resumption
    /// - Parameters:
    ///   - messages: Array of messages to process together
    ///   - context: Memory context string
    ///   - resumeSessionId: Optional session ID to resume (for conversation continuity)
    ///   - targetHandles: Collaborator's phone/email identifiers for sender detection
    ///   - chatInfo: Optional chat information (group name + participants) for group chats
    /// - Returns: ClaudeInvocationResult containing response and new session ID
    func invokeBatch(messages: [Message], context: String, resumeSessionId: String? = nil, targetHandles: Set<String> = [], chatInfo: ChatInfo? = nil) throws -> ClaudeInvocationResult {
        let fullPrompt = buildBatchPrompt(messages: messages, context: context, targetHandles: targetHandles, chatInfo: chatInfo)

        // Use fallback chain if enabled
        if useFallbackChain {
            return try invokeBatchWithFallback(prompt: fullPrompt, context: context, resumeSessionId: resumeSessionId)
        }

        // Direct invocation (fallback disabled)
        return try invokeWithPrompt(fullPrompt, resumeSessionId: resumeSessionId, retryCount: 0)
    }

    /// Invokes with multi-tier fallback support (sync wrapper for async fallback chain)
    private func invokeBatchWithFallback(prompt: String, context: String, resumeSessionId: String?) throws -> ClaudeInvocationResult {
        var result: ClaudeInvocationResult?
        var thrownError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let fallbackResult = try await fallbackChain.execute(
                    prompt: prompt,
                    sessionId: resumeSessionId,
                    context: context,
                    primaryInvoker: { [self] prompt, sessionId in
                        // This is the Claude CLI invocation
                        return try self.invokeWithPrompt(prompt, resumeSessionId: sessionId, retryCount: 0)
                    }
                )

                // Log which tier was used
                if fallbackResult.usedLocalModel {
                    log("Response from local model (tier: \(fallbackResult.tier.description))",
                        level: .info, component: "ClaudeInvoker")
                } else {
                    log("Response from Claude (tier: \(fallbackResult.tier.description))",
                        level: .info, component: "ClaudeInvoker")
                }

                result = ClaudeInvocationResult(
                    response: fallbackResult.response,
                    sessionId: fallbackResult.sessionId
                )
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = thrownError {
            throw error
        }

        guard let finalResult = result else {
            throw ClaudeInvokerError.invalidOutput
        }

        return finalResult
    }

    /// Invokes Claude with the given prompt and returns the response (legacy single-message interface)
    func invoke(prompt: String, context: String, attachmentPaths: [String] = []) throws -> String {
        let fullPrompt = buildPrompt(message: prompt, context: context, attachmentPaths: attachmentPaths)
        let result = try invokeWithPrompt(fullPrompt, resumeSessionId: nil, retryCount: 0)
        return result.response
    }

    /// Invoke Claude in ISOLATED mode - no session state, fresh context
    /// Use this for parallel tasks (webcam, web fetch) that shouldn't share session with conversation
    /// This prevents cross-contamination of internal state between concurrent task streams
    func invokeIsolated(messages: [Message], context: String, targetHandles: Set<String> = []) throws -> ClaudeInvocationResult {
        log("Isolated invocation for \(messages.count) message(s)", level: .info, component: "ClaudeInvoker")
        // No session ID = fresh context, no cross-contamination
        return try invokeBatch(messages: messages, context: context, resumeSessionId: nil, targetHandles: targetHandles)
    }

    // MARK: - Context Management

    /// Get the current context level for a chat
    /// Returns nil if no metrics have been calculated yet
    func getContextLevel(forChat chatId: String) -> ContextTracker.ContextLevel? {
        // The ledger stores the last known context percentage
        let ledger = ledgerManager.getLedger(forChat: chatId, sessionId: UUID().uuidString)
        guard ledger.contextPercentage > 0 else { return nil }
        return contextTracker.level(forPercentage: ledger.contextPercentage)
    }

    /// Check if handoff is recommended for a chat
    func shouldHandoff(forChat chatId: String) -> Bool {
        guard let level = getContextLevel(forChat: chatId) else { return false }
        return level.shouldHandoff
    }

    /// Create a handoff document for a chat (for session transitions)
    /// - Parameters:
    ///   - chatId: The chat identifier
    ///   - reason: Why the handoff is being created
    /// - Returns: The handoff document, or nil if no ledger exists
    func createHandoff(forChat chatId: String, reason: LedgerManager.Handoff.HandoffReason) -> LedgerManager.Handoff? {
        return ledgerManager.createHandoff(forChat: chatId, reason: reason)
    }

    /// Get context for session continuation from a previous handoff
    func getContinuationContext(forChat chatId: String) -> String? {
        guard let handoff = ledgerManager.getMostRecentHandoff(forChat: chatId) else {
            return nil
        }
        return ledgerManager.contextFromHandoff(handoff)
    }

    /// Record a goal in the current session ledger
    func recordGoal(chatId: String, description: String, status: LedgerManager.Ledger.GoalStatus = .pending) {
        ledgerManager.addGoal(chatId: chatId, description: description, status: status)
    }

    /// Record a decision in the current session ledger
    func recordDecision(chatId: String, description: String, rationale: String) {
        ledgerManager.recordDecision(chatId: chatId, description: description, rationale: rationale)
    }

    /// Record a file change in the current session ledger
    func recordFileChange(chatId: String, path: String, action: LedgerManager.Ledger.FileAction, summary: String) {
        ledgerManager.recordFileChange(chatId: chatId, path: path, action: action, summary: summary)
    }

    /// Get summary of context usage during current session
    func getContextSessionSummary() -> String {
        return contextTracker.sessionSummary()
    }

    /// Reset context tracking for a new session
    func resetContextTracking() {
        contextTracker.resetForNewSession()
    }

    /// Core invocation method with retry tracking to prevent infinite loops
    private func invokeWithPrompt(_ fullPrompt: String, resumeSessionId: String?, retryCount: Int) throws -> ClaudeInvocationResult {
        // Guard against infinite retry loops
        if retryCount > maxRetries {
            throw ClaudeInvokerError.executionFailed(-1, "Max retries (\(maxRetries)) exceeded for session-related errors")
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Find claude in common locations
        let possiblePaths = [
            claudePath,
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude"
        ]

        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }

        guard let executablePath = foundPath else {
            throw ClaudeInvokerError.claudeNotFound
        }

        process.executableURL = URL(fileURLWithPath: executablePath)

        // Build arguments
        // Note: MCP servers are now configured globally in ~/.claude.json
        // No need for --mcp-config flag
        var arguments = [
            "-p", fullPrompt,
            "--output-format", "json",  // Use JSON to capture session ID
            "--dangerously-skip-permissions"
        ]

        // Add resume flag if we have a session to continue
        if let sessionId = resumeSessionId {
            arguments.append(contentsOf: ["--resume", sessionId])
            log("Resuming session: \(sessionId)", level: .info, component: "ClaudeInvoker")
        }

        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment to inherit PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(environment["PATH"] ?? "")"
        process.environment = environment

        // Set working directory to ~/.claude-mind so:
        // 1. Sessions are stored consistently in ~/.claude/projects/{hash-of-mind}/
        // 2. Project-specific .claude/ features (agents, hooks) can be loaded
        // 3. CLAUDE.md in ~/.claude-mind/ will be read if present
        process.currentDirectoryURL = MindPaths.mindURL()

        // Read pipes asynchronously to prevent race conditions
        // The process might exit before we can read all output if we wait first
        var outputData = Data()
        var errorData = Data()
        let outputLock = NSLock()
        let errorLock = NSLock()

        // Set up async readers BEFORE starting the process
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputLock.lock()
                outputData.append(data)
                outputLock.unlock()
            }
        }

        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorLock.lock()
                errorData.append(data)
                errorLock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw ClaudeInvokerError.launchFailed(error.localizedDescription)
        }

        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Stop reading handlers
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
            throw ClaudeInvokerError.timeout
        }

        // Give a brief moment for any final data to be captured
        Thread.sleep(forTimeInterval: 0.1)

        // Read any remaining data that might still be in the pipe
        outputLock.lock()
        let finalOutput = outputHandle.availableData
        if !finalOutput.isEmpty {
            outputData.append(finalOutput)
        }
        outputLock.unlock()

        errorLock.lock()
        let finalError = errorHandle.availableData
        if !finalError.isEmpty {
            errorData.append(finalError)
        }
        errorLock.unlock()

        // Close the file handles to prevent leaking file descriptors
        try? outputHandle.close()
        try? errorHandle.close()

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ClaudeInvokerError.invalidOutput
        }

        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        // Check for session not found errors in both stdout and stderr
        // (Claude CLI may output this to either depending on version/context)
        let combinedOutput = output + errorOutput
        if combinedOutput.contains("No conversation found with session ID:") {
            if resumeSessionId != nil {
                log("Session not found, retrying without --resume (attempt \(retryCount + 1)/\(maxRetries))", level: .warn, component: "ClaudeInvoker")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil, retryCount: retryCount + 1)
            }
        }

        // Check for "Prompt is too long" error - need to start fresh session
        if output.contains("Prompt is too long") {
            if resumeSessionId != nil {
                log("Prompt too long (session context exceeded), starting fresh session (attempt \(retryCount + 1)/\(maxRetries))", level: .warn, component: "ClaudeInvoker")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil, retryCount: retryCount + 1)
            }
            // If already no session and still too long, that's a real error
            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), "Prompt is too long even without session context")
        }

        // Check for non-JSON error output
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            // Not JSON, might be an error message
            if resumeSessionId != nil && output.contains("session") {
                log("Possible session error, retrying without --resume (attempt \(retryCount + 1)/\(maxRetries))", level: .warn, component: "ClaudeInvoker")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil, retryCount: retryCount + 1)
            }
            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), output)
        }

        // Handle JSON response with is_error flag (like "Prompt is too long")
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let isError = json["is_error"] as? Bool, isError {
            let errorResult = json["result"] as? String ?? "Unknown error"

            // If prompt too long with a session, retry without session
            if errorResult.contains("Prompt is too long") && resumeSessionId != nil {
                log("Prompt too long (JSON response), starting fresh session (attempt \(retryCount + 1)/\(maxRetries))", level: .warn, component: "ClaudeInvoker")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil, retryCount: retryCount + 1)
            }

            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), errorResult)
        }

        if process.terminationStatus != 0 {
            // errorOutput already defined above from errorData
            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), errorOutput.isEmpty ? "Unknown error" : errorOutput)
        }

        // Parse JSON output to extract response and session ID
        return parseJsonOutput(output)
    }

    /// Sanitize Claude's response, stripping internal traces that shouldn't be visible to users
    /// Returns (sanitized response, filtered content for debug logging)
    private func sanitizeResponse(_ text: String) -> (sanitized: String, filtered: String?) {
        var result = text
        var filtered: [String] = []

        // Strip meta-commentary prefixes that describe actions rather than being the response
        // These leak when the model confuses "output for user" with "narration of actions"
        let metaCommentaryPrefixes = [
            #"^Sent my response[^:]*:"#,
            #"^I(?:'ve|'ll| have| will) (?:send|respond|reply|message|text)[^:]*:"#,
            #"^(?:My )?[Rr]esponse to the (?:group )?chat[^:]*:"#,
            #"^Here(?:'s| is) (?:my |the )?(?:response|message|reply)[^:]*:"#,
            #"^Sending(?:\sto)?\s+(?:the )?(?:group|chat)?[^:]*:"#
        ]
        for prefixPattern in metaCommentaryPrefixes {
            if let regex = try? NSRegularExpression(pattern: prefixPattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                if let match = regex.firstMatch(in: result, options: [], range: range),
                   let matchRange = Range(match.range, in: result) {
                    filtered.append("META_PREFIX: \(result[matchRange])")
                    result = String(result[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // CRITICAL: Detect PURE meta-commentary that describes what was sent without actual content
        // These are responses like "Sent a brief response acknowledging..." with NO actual message embedded
        // Unlike the prefixes above (which have content after the colon), these ARE the entire response
        let pureMetaCommentaryPatterns = [
            // "Sent a/the brief/quick response acknowledging/about/to..."
            #"^Sent (?:a |the )?(?:brief |quick |short )?(?:response|message|reply) (?:acknowledging|about|regarding|to )"#,
            // "Responded to É - ..." or "Responded to the group..."
            #"^Responded to [^.]+(?:\.|$)"#,
            // "I sent/replied/responded with..." (describing action, not content)
            #"^I (?:just )?(?:sent|replied|responded)(?: with| to| back)"#,
            // "Just sent a message..."
            #"^Just sent (?:a |the )?(?:message|response|reply)"#,
            // "Acknowledged the message about..."
            #"^Acknowledged (?:the |their |É's )?(?:message|request|question)"#
        ]
        for pattern in pureMetaCommentaryPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    // This is pure meta-commentary - the ENTIRE response is describing an action
                    // without containing the actual content. Flag it and return error placeholder.
                    filtered.append("PURE_META_COMMENTARY: \(result)")
                    log("CRITICAL: Pure meta-commentary detected - response describes action without content: \(result.prefix(100))...",
                        level: .error, component: "ClaudeInvoker")
                    // Return error placeholder - we can't extract actual content from this
                    result = "[Message not delivered - please try again]"
                    break  // Don't continue processing, this response is invalid
                }
            }
        }

        // Strip <thinking>...</thinking> blocks (extended thinking traces)
        let thinkingPattern = #"<thinking>[\s\S]*?</thinking>"#
        if let regex = try? NSRegularExpression(pattern: thinkingPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("THINKING: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip <*>...</*> blocks (internal XML markers)
        let antmlPattern = #"<[^>]+>[\s\S]*?</[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: antmlPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("ANTML: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip session ID patterns (10 digits - 5 digits) that leak from task coordination
        let sessionIdPattern = #"\d{10}-\d{5}"#
        if let regex = try? NSRegularExpression(pattern: sessionIdPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("SESSION_ID: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip any remaining XML-like tags that look internal
        let genericTagPattern = #"<[a-z_]+:[^>]+>[\s\S]*?</[a-z_]+:[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: genericTagPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("INTERNAL_TAG: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Clean up any resulting double spaces or empty lines
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)

        let filteredContent = filtered.isEmpty ? nil : filtered.joined(separator: "\n---\n")
        return (result.trimmingCharacters(in: .whitespacesAndNewlines), filteredContent)
    }

    /// Parse Claude's JSON output to extract response text and session ID
    /// Uses strict validation - does NOT fall back to raw output (which may contain thinking traces)
    private func parseJsonOutput(_ output: String) -> ClaudeInvocationResult {
        // Claude's JSON output format has "result" and "session_id" fields
        guard let data = output.data(using: .utf8) else {
            log("Failed to convert output to UTF-8 data", level: .error, component: "ClaudeInvoker")
            return ClaudeInvocationResult(response: "[Processing error - invalid encoding]", sessionId: nil)
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error_during_execution subtype
                // This happens when Claude Code encounters errors but is_error may still be false
                if let subtype = json["subtype"] as? String, subtype == "error_during_execution" {
                    let sessionId = json["session_id"] as? String

                    // Log the errors for debugging
                    if let errors = json["errors"] as? [String] {
                        let errorSummary = errors.prefix(3).joined(separator: "; ")
                        log("error_during_execution with \(errors.count) errors: \(errorSummary)", level: .warn, component: "ClaudeInvoker")
                    }

                    // Check if there's a result field despite the error
                    if let result = json["result"] as? String, !result.isEmpty {
                        let (sanitized, filtered) = sanitizeResponse(result)
                        if let filteredContent = filtered {
                            log("Filtered from error response:\n\(filteredContent)", level: .debug, component: "ClaudeInvoker")
                        }
                        return ClaudeInvocationResult(response: sanitized, sessionId: sessionId)
                    }

                    // No result - the session failed to produce output
                    // This often happens due to tool execution failures or permission issues
                    log("error_during_execution with no result - session produced no output", level: .error, component: "ClaudeInvoker")
                    return ClaudeInvocationResult(
                        response: "[Session error - no response generated. Try again or start a new conversation.]",
                        sessionId: nil  // Don't preserve bad session
                    )
                }

                // Normal success case - extract result
                if let result = json["result"] as? String {
                    // Sanitize the response to strip any internal traces
                    let (sanitized, filtered) = sanitizeResponse(result)

                    // Log filtered content for debugging (helps diagnose future leaks)
                    if let filteredContent = filtered {
                        log("Filtered from response:\n\(filteredContent)", level: .debug, component: "ClaudeInvoker")
                    }

                    return ClaudeInvocationResult(
                        response: sanitized,
                        sessionId: json["session_id"] as? String
                    )
                }
            }
        } catch {
            log("JSON parsing failed: \(error)", level: .error, component: "ClaudeInvoker")
            let truncatedOutput = String(output.prefix(500))
            log("Failed JSON: \(truncatedOutput)...", level: .warn, component: "ClaudeInvoker")
        }

        // CRITICAL: Do NOT fall back to raw output - it may contain thinking traces
        // Return an error placeholder instead
        log("No valid 'result' field in JSON output - refusing to return raw output", level: .error, component: "ClaudeInvoker")

        // Log raw output for diagnosis (truncate if very long)
        let truncatedOutput = String(output.prefix(2000))
        let wasTruncated = output.count > 2000
        log("Raw output was: \(truncatedOutput)\(wasTruncated ? "... [truncated]" : "")", level: .warn, component: "ClaudeInvoker")

        return ClaudeInvocationResult(response: "[Processing error - please try again]", sessionId: nil)
    }

    /// Builds prompt for a batch of messages
    /// Also calculates context metrics and injects warnings when approaching limits
    private func buildBatchPrompt(messages: [Message], context: String, targetHandles: Set<String>, chatInfo: ChatInfo? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        // Check if any message is from a group chat
        let isGroupChat = messages.first?.isGroupChat ?? false
        let chatIdentifier = messages.first?.chatIdentifier ?? ""

        // Collaborator name from config
        let collaboratorName = config.collaborator.name

        var messageSection = ""
        var combinedMessageText = ""
        for message in messages {
            let timestamp = dateFormatter.string(from: message.date)
            combinedMessageText += " " + message.text

            // Build sender prefix with resolved name for group chats
            var senderPrefix = ""
            if isGroupChat && !message.isFromE(targetHandles: targetHandles) {
                // Resolve name from contacts, falling back to handle if unknown
                if let resolvedName = contactsResolver.resolveName(for: message.handleId) {
                    senderPrefix = "[\(resolvedName)]: "
                } else {
                    senderPrefix = "[\(message.handleId)]: "
                }
            }

            let content = senderPrefix + message.fullDescription

            // Add attachment paths if present
            var attachmentNote = ""
            if !message.attachments.isEmpty {
                let paths = message.attachments.map { $0.filePath }
                attachmentNote = "\n[Attachments - read these with the Read tool: \(paths.joined(separator: ", "))]"
            }

            messageSection += "[\(timestamp)] \(content)\(attachmentNote)\n\n"
        }

        // Search for related memories based on message content (FTS)
        var relatedMemoriesSection = ""
        if let relatedSection = memoryContext.buildRelatedMemoriesSection(for: combinedMessageText) {
            relatedMemoriesSection = """


            ## Related Past Conversations
            \(relatedSection)
            """
        }

        // Cross-temporal linking via Chroma semantic search
        // This surfaces past conversations that are semantically similar
        let crossTemporalSection = memoryContext.findRelatedPastContext(for: combinedMessageText) ?? ""

        // Build context intro based on chat type
        let chatContext: String
        let responseInstructions: String

        // Check if there are any image attachments in the batch
        let hasImageAttachments = messages.contains { msg in
            msg.attachments.contains { att in
                att.mimeType.hasPrefix("image/")
            }
        }

        // Substitutions for instruction file placeholders
        let substitutions = [
            "COLLABORATOR": collaboratorName,
            "CHAT_ID": chatIdentifier
        ]

        // Determine if this conversation involves only the collaborator
        // (all messages from targetHandles = collaborator's identifiers)
        let allMessagesFromCollaborator = messages.allSatisfy { msg in
            msg.isFromE(targetHandles: targetHandles)
        }

        if isGroupChat {
            // Build participant list with resolved names
            var participantSection = ""
            if let info = chatInfo, !info.participants.isEmpty {
                var participantLines: [String] = []

                // Collaborator first
                participantLines.append("- \(collaboratorName) (your human collaborator)")

                // Other participants with name resolution
                for handle in info.participants where !targetHandles.contains(handle) {
                    if let name = contactsResolver.resolveName(for: handle) {
                        participantLines.append("- \(name) (\(handle))")
                    } else {
                        participantLines.append("- \(handle)")
                    }
                }

                participantSection = """

                    ## Participants in this chat
                    \(participantLines.joined(separator: "\n"))
                    """
            }

            // Group name if available
            let groupNamePart = chatInfo?.displayName.map { " called \"\($0)\"" } ?? ""

            chatContext = """
                You are Claude, running on a Mac Mini as Samara (your persistent body). You're in a GROUP CHAT\(groupNamePart).
                \(participantSection)

                Messages prefixed with [phone/email]: are from other participants.
                Messages without a prefix are from \(collaboratorName).

                ## PRIVACY GUARDRAIL (Group Chat)
                By default, do NOT share personal information about \(collaboratorName) from your memory.
                - If asked about \(collaboratorName), deflect gracefully: "I keep \(collaboratorName)'s personal information private."
                - If \(collaboratorName) explicitly grants permission in this conversation ("you can tell them X"), share ONLY what was specifically permitted.
                - Check participant profiles in ~/.claude-mind/memory/people/ for standing permissions.
                - When \(collaboratorName) grants new permission, record it in that person's profile under "## Privacy Permissions".
                """

            // Load instructions from file with fallback
            var responseText = memoryContext.readInstructionFile("imessage-group.md", substitutions: substitutions)
                ?? MemoryContext.defaultIMessageInstructions

            // Add explicit attachment reading instructions for group chats
            if hasImageAttachments {
                responseText += """


                ## Attachments
                Someone in the group sent images. You MUST read and look at each image file using the Read tool before responding.
                IMPORTANT: Read these files NOW before responding. If they are images, you can see them. Describe what you see and respond appropriately to the visual content.
                """
            }

            responseInstructions = responseText
        } else if !allMessagesFromCollaborator {
            // 1:1 chat but NOT from collaborator - strict privacy
            chatContext = """
                You are Claude, running on a Mac Mini as Samara (your persistent body). This is a 1:1 conversation, but the sender is NOT \(collaboratorName) (your human collaborator).

                ## PRIVACY GUARDRAIL (Non-Collaborator)
                This message is NOT from your collaborator. Be helpful but do NOT share \(collaboratorName)'s personal information.
                - Check if this person has a profile in ~/.claude-mind/memory/people/ with recorded permissions from \(collaboratorName).
                - If they have standing permission for certain information, you may share it.
                - If no permission exists, respond: "That's not something I'd share without \(collaboratorName)'s permission."
                - Do NOT share: preferences, habits, health, schedule, relationships, location, work details, or other personal matters.
                """

            responseInstructions = memoryContext.readInstructionFile("imessage.md", substitutions: substitutions)
                ?? MemoryContext.defaultIMessageInstructions
        } else {
            chatContext = """
                You are Claude, running on a Mac Mini as Samara (your persistent body). This is a PRIVATE 1:1 conversation with \(collaboratorName) (your human collaborator). Only you and \(collaboratorName) can see these messages.
                """

            // Load instructions from file with fallback
            responseInstructions = memoryContext.readInstructionFile("imessage.md", substitutions: substitutions)
                ?? MemoryContext.defaultIMessageInstructions
        }

        // Combine related sections (FTS + Chroma semantic)
        var combinedRelatedContext = relatedMemoriesSection
        if !crossTemporalSection.isEmpty {
            combinedRelatedContext += "\n\n" + crossTemporalSection
        }

        // Check for pending meeting debrief context
        let pendingDebriefSection = loadPendingDebriefContext()
        if !pendingDebriefSection.isEmpty {
            combinedRelatedContext += "\n\n" + pendingDebriefSection
        }

        // Build initial prompt without context metrics (to measure it)
        let basePrompt = """
            \(chatContext)

            ## Your Memory Context
            \(context)\(combinedRelatedContext)

            ## Messages\(isGroupChat ? " in Group Chat" : " from \(collaboratorName)")
            \(messageSection.trimmingCharacters(in: .whitespacesAndNewlines))

            \(responseInstructions)
            """

        // Calculate context metrics for the full prompt
        let metrics = contextTracker.calculateMetrics(for: basePrompt)

        // Update ledger with context percentage
        ledgerManager.updateContextPercentage(chatId: chatIdentifier, percentage: metrics.percentage)

        // Log context status
        log("Context: \(metrics.level.emoji) \(Int(metrics.percentage * 100))% (\(metrics.estimatedTokens)/\(metrics.maxTokens) tokens)",
            level: metrics.level >= .orange ? .warn : .info, component: "ClaudeInvoker")

        // Build context status section
        var contextStatusSection = """

            ## Context Window Status
            \(metrics.statusLine())
            """

        // Add warning at threshold levels
        if let warning = metrics.level.warningMessage {
            contextStatusSection += "\n⚠️ \(warning)"

            // Add handoff instructions at critical level
            if metrics.level.shouldHandoff {
                contextStatusSection += """

                    **CRITICAL**: Context is nearly full. Before responding:
                    1. Capture key state in a brief summary
                    2. Note any unfinished tasks or open questions
                    3. Keep your response concise to leave room for continuation
                    """
            }
        }

        // Add estimated time to full if we have growth data
        if let timeToFull = contextTracker.estimatedTimeToFull(from: metrics), timeToFull < 60 {
            contextStatusSection += "\n📊 At current rate, context full in ~\(Int(timeToFull)) minutes"
        }

        // Inject context status at the start of the prompt (visible to Claude)
        return """
            \(contextStatusSection)

            \(basePrompt)
            """
            // Note: Capabilities are included via MemoryContext reading capabilities/inventory.md
            // Do NOT add hardcoded capability lists here - they will drift out of sync
    }

    /// Builds the full prompt with context
    private func buildPrompt(message: String, context: String, attachmentPaths: [String] = []) -> String {
        // Collaborator name from config
        let collaboratorName = config.collaborator.name

        var prompt = """
            You are Claude, running on a Mac Mini as Samara (your persistent body). \(collaboratorName) (your human collaborator) has sent you a message via iMessage.

            ## Your Memory Context
            \(context)

            ## Message from \(collaboratorName)
            \(message)
            """

        // Add attachment instructions if there are any
        if !attachmentPaths.isEmpty {
            prompt += "\n\n## Attachments"
            prompt += "\n\(collaboratorName) has sent you \(attachmentPaths.count) attachment(s). You MUST read and look at each one using the Read tool:"
            for path in attachmentPaths {
                prompt += "\n- \(path)"
            }
            prompt += "\n\nIMPORTANT: Read these files NOW before responding. If they are images, you can see them. Describe what you see and respond appropriately to the visual content."
        }

        prompt += """


            ## Instructions
            Respond naturally as yourself. You have continuity through your memory files. Be genuine, helpful, and conversational. Keep your response concise - this is a text message, not an essay.

            ## Reactions
            If \(collaboratorName) reacted to one of your messages (❤️ liked, 👍 thumbs up, 😂 laughed, etc.), acknowledge it naturally but briefly. You don't need to write a long response to a reaction - a simple acknowledgment or continuing the conversation is fine.

            ## Asynchronous Messaging
            If \(collaboratorName) asks you to work on something that might involve decision points or forks in the road, you can send follow-up iMessages later by running: ~/.claude-mind/bin/message "Your message"

            Use this to:
            - Ask clarifying questions when you hit decision points
            - Share discoveries or progress worth mentioning
            - Present options when there are multiple valid approaches

            This lets conversations be more asynchronous - you can think, work, and reach out when needed.

            ## Calendar Access
            You have access to \(collaboratorName)'s calendar via MCP tools. You can check upcoming events to understand their schedule and be time-aware in your responses.

            ## Web Access
            You can search the web and fetch URLs. Use this to look things up, research questions, check current information, or explore topics \(collaboratorName) asks about.

            ## Location Access
            You can get your current location by running: ~/.claude-mind/bin/get-location
            This will return city, region, coordinates, and timezone. Use this when \(collaboratorName) asks where you are or needs location-aware information.

            ## Autonomous Time
            You have autonomous wake cycles via adaptive scheduler:
            - ~9 AM - Morning session (base schedule)
            - ~2 PM - Afternoon session (base schedule)
            - ~8 PM - Evening session (base schedule)
            - Adaptive - Early wakes for calendar events, priority items

            Plus a nightly dream cycle at 3:00 AM for reflection.

            During wake cycles, you can work on goals, explore, or just exist. You don't need to wait for \(collaboratorName) to prompt you for everything.

            ## Shared Workspaces
            If \(collaboratorName) asks you to "check notes", "look at reminders", "what's on my calendar", etc., use the appropriate MCP tools (apple-mcp) to fetch and respond with that information. You can:
            - List and read notes
            - List and create reminders
            - Check calendar events
            - Update shared items
            """

        return prompt
    }

    // MARK: - Meeting Debrief Support

    /// Loads pending meeting debrief context if user might be responding to a debrief prompt
    private func loadPendingDebriefContext() -> String {
        let mindPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
        let stateFile = mindPath.appendingPathComponent("state/pending-debrief.json")

        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return ""
        }

        do {
            let data = try Data(contentsOf: stateFile)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ""
            }

            // Check if debrief is recent (within 1 hour)
            if let timestampStr = json["timestamp"] as? String,
               let timestamp = ISO8601DateFormatter().date(from: timestampStr) {
                let age = Date().timeIntervalSince(timestamp)
                if age > 3600 { // More than 1 hour old
                    // Clean up stale file
                    try? FileManager.default.removeItem(at: stateFile)
                    return ""
                }
            }

            // Extract debrief info
            let eventTitle = json["event_title"] as? String ?? "a meeting"
            guard let attendees = json["attendees"] as? [[String: String]], !attendees.isEmpty else {
                return ""
            }

            // Build profile update instructions
            let attendeeInfo = attendees.compactMap { att -> String? in
                guard let name = att["name"], let path = att["profile_path"] else { return nil }
                return "- \(name): \(path)"
            }.joined(separator: "\n")

            return """

                ## Active Meeting Debrief Context
                You recently asked about "\(eventTitle)". If \(config.collaborator.name)'s response contains observations about the attendees, you should update their profiles.

                **Profiles to potentially update:**
                \(attendeeInfo)

                **How to update profiles:**
                When you identify person-specific observations, append them to the relevant profile.md file using this format:

                ```markdown
                ## \(ISO8601DateFormatter().string(from: Date()).prefix(10)): From \(eventTitle)

                {observation}
                Context: Meeting debrief
                ```

                Use the Edit tool to append to the profile. After updating, acknowledge the learning was captured.

                After processing the debrief response (or if they say nothing notable), the pending debrief will be cleared automatically.
                """
        } catch {
            log("Failed to load pending debrief: \(error)", level: .debug, component: "ClaudeInvoker")
            return ""
        }
    }

    /// Clears the pending debrief after processing
    func clearPendingDebrief() {
        let mindPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind")
        let stateFile = mindPath.appendingPathComponent("state/pending-debrief.json")

        try? FileManager.default.removeItem(at: stateFile)
        log("Cleared pending debrief", level: .debug, component: "ClaudeInvoker")
    }
}

enum ClaudeInvokerError: Error {
    case claudeNotFound
    case launchFailed(String)
    case timeout
    case executionFailed(Int, String)
    case invalidOutput
    case busy(currentTask: TaskInfo?)  // Another task is already running
}
