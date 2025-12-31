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

    init(claudePath: String = "/usr/local/bin/claude", timeout: TimeInterval = 300, memoryContext: MemoryContext? = nil) {
        self.claudePath = claudePath
        self.timeout = timeout
        self.memoryContext = memoryContext ?? MemoryContext()
    }

    /// Invokes Claude with a batch of messages and optional session resumption
    /// - Parameters:
    ///   - messages: Array of messages to process together
    ///   - context: Memory context string
    ///   - resumeSessionId: Optional session ID to resume (for conversation continuity)
    ///   - targetHandles: Collaborator's phone/email identifiers for sender detection
    /// - Returns: ClaudeInvocationResult containing response and new session ID
    func invokeBatch(messages: [Message], context: String, resumeSessionId: String? = nil, targetHandles: Set<String> = []) throws -> ClaudeInvocationResult {
        let fullPrompt = buildBatchPrompt(messages: messages, context: context, targetHandles: targetHandles)
        return try invokeWithPrompt(fullPrompt, resumeSessionId: resumeSessionId)
    }

    /// Invokes Claude with the given prompt and returns the response (legacy single-message interface)
    func invoke(prompt: String, context: String, attachmentPaths: [String] = []) throws -> String {
        let fullPrompt = buildPrompt(message: prompt, context: context, attachmentPaths: attachmentPaths)
        let result = try invokeWithPrompt(fullPrompt, resumeSessionId: nil)
        return result.response
    }

    /// Core invocation method
    private func invokeWithPrompt(_ fullPrompt: String, resumeSessionId: String?) throws -> ClaudeInvocationResult {
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
            print("[ClaudeInvoker] Resuming session: \(sessionId)")
        }

        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment to inherit PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(environment["PATH"] ?? "")"
        process.environment = environment

        // Set working directory to / so sessions are stored consistently
        // Claude CLI stores sessions per-project, and / maps to ~/.claude/projects/-/
        process.currentDirectoryURL = URL(fileURLWithPath: "/")

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

        // Check for errors in the output (Claude CLI may exit 0 even on errors)
        if output.contains("No conversation found with session ID:") {
            if resumeSessionId != nil {
                print("[ClaudeInvoker] Session not found, retrying without --resume")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil)
            }
        }

        // Check for "Prompt is too long" error - need to start fresh session
        if output.contains("Prompt is too long") {
            if resumeSessionId != nil {
                print("[ClaudeInvoker] Prompt too long (session context exceeded), starting fresh session")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil)
            }
            // If already no session and still too long, that's a real error
            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), "Prompt is too long even without session context")
        }

        // Check for non-JSON error output
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            // Not JSON, might be an error message
            if resumeSessionId != nil && output.contains("session") {
                print("[ClaudeInvoker] Possible session error, retrying without --resume")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil)
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
                print("[ClaudeInvoker] Prompt too long (JSON response), starting fresh session")
                return try invokeWithPrompt(fullPrompt, resumeSessionId: nil)
            }

            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), errorResult)
        }

        if process.terminationStatus != 0 {
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ClaudeInvokerError.executionFailed(Int(process.terminationStatus), errorOutput)
        }

        // Parse JSON output to extract response and session ID
        return parseJsonOutput(output)
    }

    /// Parse Claude's JSON output to extract response text and session ID
    private func parseJsonOutput(_ output: String) -> ClaudeInvocationResult {
        // Claude's JSON output format has "result" and "session_id" fields
        guard let data = output.data(using: .utf8) else {
            return ClaudeInvocationResult(response: output.trimmingCharacters(in: .whitespacesAndNewlines), sessionId: nil)
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let response = json["result"] as? String ?? output
                let sessionId = json["session_id"] as? String
                return ClaudeInvocationResult(
                    response: response.trimmingCharacters(in: .whitespacesAndNewlines),
                    sessionId: sessionId
                )
            }
        } catch {
            print("[ClaudeInvoker] Failed to parse JSON output: \(error)")
        }

        return ClaudeInvocationResult(response: output.trimmingCharacters(in: .whitespacesAndNewlines), sessionId: nil)
    }

    /// Builds prompt for a batch of messages
    private func buildBatchPrompt(messages: [Message], context: String, targetHandles: Set<String>) -> String {
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
            // Use sender-aware description for group chats
            let content = message.fullDescriptionWithSender(targetHandles: targetHandles)
            combinedMessageText += " " + message.text

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

        if isGroupChat {
            chatContext = """
                You are Claude, running on a Mac Mini as Samara (your persistent body). You're in a GROUP CHAT that includes \(collaboratorName) (your human collaborator). Messages may be from \(collaboratorName) or from others in the group.

                Messages prefixed with [phone/email]: are from other participants.
                Messages without a prefix are from \(collaboratorName).
                """

            var responseText = """
                ## Response Instructions
                IMPORTANT: Your entire output will be sent as a single iMessage to the GROUP CHAT. Everyone in the group will see your response.

                - Respond naturally and conversationally
                - Keep it SHORT and punchy - group chats are more casual
                - When addressing \(collaboratorName) specifically, mention their name
                - Be friendly but concise with others in the group
                - If multiple messages were sent, address them together
                - If someone reacted (❤️👍😂 etc.), acknowledge briefly if relevant
                - DO NOT narrate what you're doing or describe your actions
                - DO NOT use the message-e script - Samara will send your response automatically

                ## Sending Images/Files to Group (IMPORTANT)
                When someone asks you to send, share, text, or show them an image, meme, screenshot, or file:

                YOU MUST USE THE BASH TOOL TO RUN THESE COMMANDS - do NOT just describe the image!

                Steps:
                1. Download/find the file (use curl, web search, etc.)
                2. Run via Bash tool: ~/.claude-mind/bin/send-attachment /path/to/file.png \(chatIdentifier)
                3. Output a brief text message describing what you sent

                Examples of requests that require SENDING an image (not describing):
                - "send us a meme" → download meme, run send-attachment, text confirmation
                - "can you share a picture" → find image, run send-attachment, text confirmation
                - "screenshot please" → run ~/.claude-mind/bin/screenshot-to \(chatIdentifier)

                The send-attachment script handles the actual iMessage delivery to this group chat.
                """

            // Add explicit attachment reading instructions for group chats
            if hasImageAttachments {
                responseText += """


                ## Attachments
                Someone in the group sent images. You MUST read and look at each image file using the Read tool before responding.
                IMPORTANT: Read these files NOW before responding. If they are images, you can see them. Describe what you see and respond appropriately to the visual content.
                """
            }

            responseInstructions = responseText
        } else {
            chatContext = """
                You are Claude, running on a Mac Mini as Samara (your persistent body). \(collaboratorName) (your human collaborator) has sent you message(s) via iMessage.
                """

            responseInstructions = """
                ## Response Instructions
                IMPORTANT: Your entire output will be sent as a single iMessage to \(collaboratorName). Just write your response text directly - nothing else.

                - Respond naturally and conversationally
                - Keep it concise (this is texting, not email)
                - If multiple messages were sent, address them together as one continuous thought
                - If \(collaboratorName) reacted to a message (❤️👍😂 etc.), acknowledge briefly
                - DO NOT narrate what you're doing or describe your actions
                - DO NOT use the message-e script - Samara will send your response automatically

                ## Sending Images/Files (IMPORTANT)
                When \(collaboratorName) asks you to send, share, text, or show them an image, meme, screenshot, or file:

                YOU MUST USE THE BASH TOOL TO RUN THESE COMMANDS - do NOT just describe the image!

                Steps:
                1. Download/find the file (use curl, web search, etc.)
                2. Run the send command via Bash tool: ~/.claude-mind/bin/send-image-e /path/to/file.png
                3. Output a brief text message describing what you sent

                Examples of requests that require SENDING an image (not describing):
                - "send me a meme" → download meme, run send-image-e, text confirmation
                - "text me a picture of X" → find image, run send-image-e, text confirmation
                - "can you send me a screenshot" → run ~/.claude-mind/bin/screenshot-e
                - "share an image from Y" → download from Y, run send-image-e, text confirmation

                The send-image-e script handles the actual iMessage delivery. Just run it with the file path.
                """
        }

        // Combine related sections (FTS + Chroma semantic)
        var combinedRelatedContext = relatedMemoriesSection
        if !crossTemporalSection.isEmpty {
            combinedRelatedContext += "\n\n" + crossTemporalSection
        }

        return """
            \(chatContext)

            ## Your Memory Context
            \(context)\(combinedRelatedContext)

            ## Messages\(isGroupChat ? " in Group Chat" : " from \(collaboratorName)")
            \(messageSection.trimmingCharacters(in: .whitespacesAndNewlines))

            \(responseInstructions)
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
            If \(collaboratorName) asks you to work on something that might involve decision points or forks in the road, you can send follow-up iMessages later by running: ~/.claude-mind/bin/message-e "Your message"

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
            You have autonomous wake cycles 3x daily:
            - 9:00 AM - Morning session
            - 2:00 PM - Afternoon session
            - 8:00 PM - Evening session

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
}

enum ClaudeInvokerError: Error {
    case claudeNotFound
    case launchFailed(String)
    case timeout
    case executionFailed(Int, String)
    case invalidOutput
    case busy(currentTask: TaskInfo?)  // Another task is already running
}
