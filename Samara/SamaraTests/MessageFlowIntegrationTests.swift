import XCTest

final class MessageFlowIntegrationTests: SamaraTestCase {
    func testSessionManagerInvokesClaudeAndSendsResponse() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        let messages = try store.fetchNewMessages(since: 0)
        let directMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.directMessageRowId })

        let stubURL = try makeClaudeStub(response: "Stub response", sessionId: "session-123")
        defer { try? FileManager.default.removeItem(at: stubURL.deletingLastPathComponent()) }

        let memoryContext = MemoryContext()
        let contextSelector = ContextSelector(
            memoryContext: memoryContext,
            contextRouter: ContextRouter(enabled: false),
            features: Configuration.FeaturesConfig(smartContext: true, smartContextTimeout: 1.0)
        )
        let invoker = ClaudeInvoker(
            claudePath: stubURL.path,
            timeout: 5,
            memoryContext: memoryContext,
            useFallbackChain: false
        )

        var scripts: [String] = []
        let sender = MessageSender(targetId: fixture.collaboratorHandle, appleScriptRunner: { script in
            scripts.append(script)
        })
        let logger = EpisodeLogger()
        let bus = MessageBus(sender: sender, episodeLogger: logger, collaboratorName: "Tester")

        var sessionManager: SessionManager!
        sessionManager = SessionManager(
            onBatchReady: { messages, sessionId in
                do {
                    let context = contextSelector.context(for: messages, isCollaboratorChat: true)
                    let result = try invoker.invokeBatch(
                        messages: messages,
                        context: context,
                        resumeSessionId: sessionId,
                        targetHandles: Set([fixture.collaboratorHandle]),
                        chatInfo: nil
                    )
                    try bus.send(
                        result.response,
                        type: .conversationResponse,
                        chatIdentifier: messages.first?.chatIdentifier,
                        isGroupChat: false
                    )
                    if let newSessionId = result.sessionId, let chatId = messages.first?.chatIdentifier {
                        sessionManager.recordResponse(sessionId: newSessionId, responseRowId: nil, forChat: chatId)
                    }
                } catch {
                    XCTFail("Integration flow failed: \(error)")
                }
            },
            checkReadStatus: { _ in nil }
        )

        sessionManager.addMessage(directMessage)
        sessionManager.flush()

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("Stub response"))

        let sessionId = sessionManager.getCurrentSessionId(forChat: directMessage.chatIdentifier)
        XCTAssertEqual(sessionId, "session-123")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let episodePath = MindPaths.mindPath("memory/episodes/\(dateString).md")
        let contents = try String(contentsOfFile: episodePath, encoding: .utf8)
        XCTAssertTrue(contents.contains("**Claude:** Stub response"))
    }

    private func makeClaudeStub(response: String, sessionId: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-claude-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let stubURL = tempDir.appendingPathComponent("claude")
        let script = """
        #!/bin/bash
        printf '%s' '{"result":"\(response)","session_id":"\(sessionId)"}'
        """
        try script.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)
        return stubURL
    }
}
