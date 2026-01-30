import Foundation

/// Chooses between smart and legacy context building for different inputs.
final class ContextSelector {
    private let memoryContext: MemoryContext
    private let contextRouter: ContextRouter
    private let features: Configuration.FeaturesConfig

    init(
        memoryContext: MemoryContext,
        contextRouter: ContextRouter,
        features: Configuration.FeaturesConfig = config.featuresConfig
    ) {
        self.memoryContext = memoryContext
        self.contextRouter = contextRouter
        self.features = features
    }

    func context(for messages: [Message], isCollaboratorChat: Bool) -> String {
        guard features.smartContext ?? true else {
            let context = memoryContext.buildContext(isCollaboratorChat: isCollaboratorChat)
            logContextMetrics(context: context, mode: "legacy", needs: nil)
            return context
        }

        let needs = contextRouter.analyze(messages)
        let context = memoryContext.buildSmartContext(needs: needs, isCollaboratorChat: isCollaboratorChat)
        logContextMetrics(context: context, mode: "smart", needs: needs)
        return context
    }

    func context(forText text: String, isCollaboratorChat: Bool, handleId: String? = nil, chatIdentifier: String? = nil) -> String {
        let handleValue = handleId ?? config.collaborator.phone
        let chatValue = chatIdentifier ?? handleValue
        let syntheticMessage = Message(
            rowId: 0,
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: handleValue,
            chatId: 0,
            isGroupChat: false,
            chatIdentifier: chatValue,
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )
        return context(for: [syntheticMessage], isCollaboratorChat: isCollaboratorChat)
    }

    private func logContextMetrics(context: String, mode: String, needs: ContextRouter.ContextNeeds?) {
        let tokenEstimate = MemoryContext.estimateTokens(context)
        var details = "Context built (\(mode)): tokens=\(tokenEstimate) chars=\(context.count)"

        if let needs {
            details += " needsTokens=\(needs.estimatedTokens)"
            details += " modules=\(needs.requiredModules.count)"
            details += " searches=\(needs.searchQueries.count)"
        }

        if let stats = memoryContext.cacheStatsSnapshot() {
            details += " cacheHits=\(stats.hits)"
            details += " cacheMisses=\(stats.misses)"
            details += " cacheEvictions=\(stats.evictions)"
            details += " cacheEntries=\(stats.entries)"
            details += " cacheTokens=\(stats.cachedTokens)"
        } else {
            details += " cache=none"
        }

        log(details, level: .info, component: "ContextSelector")
    }
}
