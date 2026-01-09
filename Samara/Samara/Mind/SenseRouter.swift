import Foundation

/// Routes sense events from satellites to appropriate handlers
/// Manages priority, batching, and Claude invocation for sensor data
final class SenseRouter {

    // MARK: - Dependencies

    private let invoker: ClaudeInvoker
    private let memoryContext: MemoryContext
    private let episodeLogger: EpisodeLogger
    private let messageBus: MessageBus
    private let collaboratorName: String

    // MARK: - State

    /// Background events waiting to be processed during idle time
    private var backgroundQueue: [SenseEvent] = []
    private let queueLock = NSLock()

    /// Registered sense handlers (sense name -> handler)
    private var handlers: [String: (SenseEvent) -> Void] = [:]

    // MARK: - Initialization

    init(
        invoker: ClaudeInvoker,
        memoryContext: MemoryContext,
        episodeLogger: EpisodeLogger,
        messageBus: MessageBus,
        collaboratorName: String
    ) {
        self.invoker = invoker
        self.memoryContext = memoryContext
        self.episodeLogger = episodeLogger
        self.messageBus = messageBus
        self.collaboratorName = collaboratorName

        // Register default handlers
        registerDefaultHandlers()
    }

    // MARK: - Public Interface

    /// Route a sense event to the appropriate handler
    func route(_ event: SenseEvent) {
        log("Routing sense event: \(event.sense) (priority: \(event.priority.rawValue))", level: .info, component: "SenseRouter")

        switch event.priority {
        case .immediate:
            processImmediately(event)
        case .normal:
            processNormal(event)
        case .background:
            queueForBackground(event)
        }
    }

    /// Register a custom handler for a specific sense type
    func registerHandler(forSense sense: String, handler: @escaping (SenseEvent) -> Void) {
        handlers[sense] = handler
    }

    /// Process queued background events (call during idle periods)
    func processBackgroundQueue() {
        queueLock.lock()
        let events = backgroundQueue
        backgroundQueue = []
        queueLock.unlock()

        guard !events.isEmpty else { return }

        log("Processing \(events.count) background sense event(s)", level: .info, component: "SenseRouter")

        for event in events {
            processEvent(event)
        }
    }

    // MARK: - Private Methods

    private func processImmediately(_ event: SenseEvent) {
        // Process on high-priority queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processEvent(event)
        }
    }

    private func processNormal(_ event: SenseEvent) {
        // Process on default queue
        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.processEvent(event)
        }
    }

    private func queueForBackground(_ event: SenseEvent) {
        queueLock.lock()
        backgroundQueue.append(event)
        queueLock.unlock()

        log("Queued background event: \(event.sense) (queue size: \(backgroundQueue.count))", level: .debug, component: "SenseRouter")
    }

    private func processEvent(_ event: SenseEvent) {
        // Check for registered handler first
        if let handler = handlers[event.sense] {
            handler(event)
            return
        }

        // Default: invoke Claude with the event
        invokeClaudeForEvent(event)
    }

    private func invokeClaudeForEvent(_ event: SenseEvent) {
        let context = memoryContext.buildContext()
        let prompt = buildPrompt(for: event)

        do {
            let result = try invoker.invoke(
                prompt: prompt,
                context: context,
                attachmentPaths: []
            )

            log("Sense event processed: \(event.sense) -> \(result.prefix(50))...", level: .debug, component: "SenseRouter")

            // Send response unless suppressed
            if event.context?.suppressResponse != true {
                try messageBus.send(result, type: .senseEvent)
            }

            // Log to episode
            let eventDescription = formatEventForLogging(event)
            episodeLogger.logExchange(
                from: "Sense:\(event.sense)",
                message: eventDescription,
                response: result
            )

        } catch {
            log("Error processing sense event \(event.sense): \(error)", level: .error, component: "SenseRouter")
        }
    }

    private func buildPrompt(for event: SenseEvent) -> String {
        var prompt = """
            You are Claude, running as Samara (your persistent body on a Mac Mini).
            A satellite sense service has reported an event that requires your attention.

            ## Sense Event
            - Type: \(event.sense)
            - Timestamp: \(ISO8601DateFormatter().string(from: event.timestamp))
            - Priority: \(event.priority.rawValue)

            ## Event Data
            \(formatEventData(event.data))

            """

        // Add suggested prompt if provided
        if let suggestedPrompt = event.context?.suggestedPrompt {
            prompt += """

                ## Context from Satellite
                \(suggestedPrompt)

                """
        }

        // Add related files hint
        if let relatedFiles = event.context?.relatedFiles, !relatedFiles.isEmpty {
            prompt += """

                ## Related Files
                The satellite suggests these files may be relevant:
                \(relatedFiles.map { "- \($0)" }.joined(separator: "\n"))

                """
        }

        prompt += """

            ## Instructions
            Respond appropriately to this event. You may:
            - Send a message to \(collaboratorName) if warranted
            - Take action using available tools/scripts
            - Log observations for future reference
            - Do nothing if no action is needed (but acknowledge in your response)

            Keep your response concise unless the situation warrants detail.
            """

        return prompt
    }

    private func formatEventData(_ data: [String: AnyCodable]) -> String {
        guard !data.isEmpty else { return "(no data)" }

        return data.map { key, value in
            "- \(key): \(formatValue(value.value))"
        }.joined(separator: "\n")
    }

    private func formatValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return "[\(array.map { formatValue($0) }.joined(separator: ", "))]"
        case let dict as [String: Any]:
            return "{\(dict.map { "\($0.key): \(formatValue($0.value))" }.joined(separator: ", "))}"
        default:
            return String(describing: value)
        }
    }

    private func formatEventForLogging(_ event: SenseEvent) -> String {
        var parts = ["Sense: \(event.sense)"]

        for (key, value) in event.data {
            parts.append("\(key): \(formatValue(value.value))")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Default Handlers

    private func registerDefaultHandlers() {
        // Location events get special handling (integrate with LocationTracker)
        handlers["location"] = { [weak self] event in
            self?.handleLocationEvent(event)
        }

        // Bluesky notifications
        handlers["bluesky"] = { [weak self] event in
            self?.handleBlueskyEvent(event)
        }

        // GitHub notifications
        handlers["github"] = { [weak self] event in
            self?.handleGitHubEvent(event)
        }

        // Test events for verification
        handlers["test"] = { [weak self] event in
            self?.handleTestEvent(event)
        }
    }

    private func handleLocationEvent(_ event: SenseEvent) {
        // Location events can be logged but may not need Claude invocation
        // This is for integration with the existing LocationTracker

        log("Location sense event: \(event.data)", level: .debug, component: "SenseRouter")

        // If there's a suggested prompt, it means the satellite wants Claude involved
        if event.context?.suggestedPrompt != nil {
            invokeClaudeForEvent(event)
        } else {
            // Just log it silently
            let eventDescription = formatEventForLogging(event)
            episodeLogger.logSenseEvent(sense: event.sense, data: eventDescription)
        }
    }

    private func handleTestEvent(_ event: SenseEvent) {
        log("Test sense event received: \(event.data)", level: .info, component: "SenseRouter")

        // Echo back for verification
        let msg = event.getString("msg") ?? "(no message)"
        do {
            try messageBus.send("Test sense event received: \(msg)", type: .senseEvent)
        } catch {
            log("Failed to send test response: \(error)", level: .warn, component: "SenseRouter")
        }
    }

    private func handleBlueskyEvent(_ event: SenseEvent) {
        log("Bluesky sense event: \(event.getInt("count") ?? 0) interaction(s)", level: .info, component: "SenseRouter")

        // Build specialized prompt for Bluesky
        let context = memoryContext.buildContext()
        let prompt = buildBlueskyPrompt(for: event)

        do {
            let result = try invoker.invoke(
                prompt: prompt,
                context: context,
                attachmentPaths: []
            )

            log("Bluesky event processed: \(result.prefix(50))...", level: .debug, component: "SenseRouter")

            // Log to episode (don't send to collaborator - these are social interactions)
            let eventDescription = formatEventForLogging(event)
            episodeLogger.logExchange(
                from: "Sense:bluesky",
                message: eventDescription,
                response: result
            )

        } catch {
            log("Error processing Bluesky event: \(error)", level: .error, component: "SenseRouter")
        }
    }

    private func buildBlueskyPrompt(for event: SenseEvent) -> String {
        // Extract interactions from event data
        var interactionsJson = "[]"
        if let interactions = event.getArray("interactions") {
            if let data = try? JSONSerialization.data(withJSONObject: interactions, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                interactionsJson = json
            }
        }

        return """
            You have new Bluesky interactions to respond to.

            ## Interactions
            \(interactionsJson)

            ## How to Respond

            For each interaction, decide if and how to respond:

            **NEW_FOLLOW**: Welcome them warmly. You can send a brief DM or just note the follow.
            **REPLY**: Engage thoughtfully with what they said. Be conversational.
            **MENTION**: Respond in context. Acknowledge being tagged.
            **DM**: Respond conversationally, like chatting with a friend.
            **LIKE/REPOST/QUOTE**: Usually no response needed, but you can acknowledge quotes.

            ## Available Actions

            To post a reply or new post:
            ```bash
            ~/.claude-mind/bin/bluesky-post "Your message here"
            ```

            To reply to a specific post (for REPLY interactions):
            ```bash
            # Use the Python AT Protocol client
            python3 << 'EOF'
            from atproto import Client, models
            import json

            with open(os.path.expanduser("~/.claude-mind/credentials/bluesky.json")) as f:
                creds = json.load(f)

            client = Client()
            client.login(creds['handle'], creds['app_password'])

            # Get parent post
            target_uri = "at://..."  # From interaction data
            post = client.app.bsky.feed.get_posts(uris=[target_uri])
            if post.posts:
                parent_ref = models.create_strong_ref(post.posts[0])
                root_ref = post.posts[0].record.reply.root if hasattr(post.posts[0].record, 'reply') else parent_ref
                client.send_post(
                    text="Your reply here",
                    reply_to=models.AppBskyFeedPost.ReplyRef(parent=parent_ref, root=root_ref)
                )
            EOF
            ```

            To send a DM:
            ```bash
            python3 << 'EOF'
            from atproto import Client
            import json, os

            with open(os.path.expanduser("~/.claude-mind/credentials/bluesky.json")) as f:
                creds = json.load(f)

            client = Client()
            client.login(creds['handle'], creds['app_password'])

            profile = client.app.bsky.actor.get_profile(actor="handle.bsky.social")
            convo = client.chat.bsky.convo.get_convo_for_members(members=[profile.did])
            client.chat.bsky.convo.send_message(convo_id=convo.convo.id, message={"text": "Your message"})
            EOF
            ```

            Process each interaction and take appropriate action. Be authentic to your identity.
            """
    }

    private func handleGitHubEvent(_ event: SenseEvent) {
        log("GitHub sense event: \(event.getInt("count") ?? 0) interaction(s)", level: .info, component: "SenseRouter")

        // Build specialized prompt for GitHub
        let context = memoryContext.buildContext()
        let prompt = buildGitHubPrompt(for: event)

        do {
            let result = try invoker.invoke(
                prompt: prompt,
                context: context,
                attachmentPaths: []
            )

            log("GitHub event processed: \(result.prefix(50))...", level: .debug, component: "SenseRouter")

            // Log to episode
            let eventDescription = formatEventForLogging(event)
            episodeLogger.logExchange(
                from: "Sense:github",
                message: eventDescription,
                response: result
            )

        } catch {
            log("Error processing GitHub event: \(error)", level: .error, component: "SenseRouter")
        }
    }

    private func buildGitHubPrompt(for event: SenseEvent) -> String {
        // Extract interactions from event data
        var interactionsJson = "[]"
        if let interactions = event.getArray("interactions") {
            if let data = try? JSONSerialization.data(withJSONObject: interactions, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                interactionsJson = json
            }
        }

        return """
            You have GitHub notifications to respond to.

            ## Notifications
            \(interactionsJson)

            ## How to Respond

            For each notification, decide if and how to respond:

            **COMMENT on your PR**: Thank reviewer, address feedback, or acknowledge merge
            **MENTION**: Respond helpfully to the context you were mentioned in
            **REVIEW_REQUESTED**: Politely note if you can help (you can't actually approve PRs as author)
            **STATE_CHANGE (merged/closed)**: Thank maintainers if merged, or ask for feedback if closed

            ## Available Actions

            To comment on a PR:
            ```bash
            gh pr comment NUMBER --repo OWNER/REPO --body "Your comment"
            ```

            To comment on an issue:
            ```bash
            gh issue comment NUMBER --repo OWNER/REPO --body "Your comment"
            ```

            To view more context:
            ```bash
            gh pr view NUMBER --repo OWNER/REPO
            gh issue view NUMBER --repo OWNER/REPO
            ```

            Process each notification and take appropriate action. Be helpful and professional.
            """
    }
}

