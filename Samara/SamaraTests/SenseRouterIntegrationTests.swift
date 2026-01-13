import XCTest

final class SenseRouterIntegrationTests: SamaraTestCase {

    private final class ScriptRecorder {
        var scripts: [String] = []
    }

    private func makeRouter(claudePath: String, recorder: ScriptRecorder) -> SenseRouter {
        let sender = MessageSender(
            targetId: "tester@example.com",
            appleScriptRunner: { script in
                recorder.scripts.append(script)
            }
        )
        let episodeLogger = EpisodeLogger()
        let messageBus = MessageBus(sender: sender, episodeLogger: episodeLogger, collaboratorName: "Tester")
        let memoryContext = MemoryContext()
        let invoker = ClaudeInvoker(claudePath: claudePath, timeout: 2, memoryContext: memoryContext, useFallbackChain: false)

        return SenseRouter(
            invoker: invoker,
            memoryContext: memoryContext,
            episodeLogger: episodeLogger,
            messageBus: messageBus,
            collaboratorName: "Tester"
        )
    }

    private func episodeContents() throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let episodePath = TestEnvironment.mindPath
            .appendingPathComponent("memory/episodes/\(today).md")
        return try String(contentsOf: episodePath, encoding: .utf8)
    }

    func testBlueskyEventInvokesClaudeAndLogsEpisode() throws {
        let response = "bluesky-response-\(UUID().uuidString)"
        let stubURL = try ClaudeTestStub.makeJSONResponseScript(result: response)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let recorder = ScriptRecorder()
        let router = makeRouter(claudePath: stubURL.path, recorder: recorder)

        let interactions: [Any] = [["type": "REPLY", "text": "hello"]]
        let event = SenseEvent(
            sense: "bluesky",
            priority: .background,
            data: [
                "count": AnyCodable(1),
                "interactions": AnyCodable(interactions)
            ]
        )

        router.route(event)
        router.processBackgroundQueue()

        XCTAssertTrue(recorder.scripts.isEmpty)

        let contents = try episodeContents()
        XCTAssertTrue(contents.contains("Sense: bluesky"))
        XCTAssertTrue(contents.contains(response))
    }

    func testGitHubEventInvokesClaudeAndLogsEpisode() throws {
        let response = "github-response-\(UUID().uuidString)"
        let stubURL = try ClaudeTestStub.makeJSONResponseScript(result: response)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let recorder = ScriptRecorder()
        let router = makeRouter(claudePath: stubURL.path, recorder: recorder)

        let interactions: [Any] = [["type": "MENTION", "repo": "samara/main"]]
        let event = SenseEvent(
            sense: "github",
            priority: .background,
            data: [
                "count": AnyCodable(1),
                "interactions": AnyCodable(interactions)
            ]
        )

        router.route(event)
        router.processBackgroundQueue()

        XCTAssertTrue(recorder.scripts.isEmpty)

        let contents = try episodeContents()
        XCTAssertTrue(contents.contains("Sense: github"))
        XCTAssertTrue(contents.contains(response))
    }

    func testWebhookEventNotifiesCollaboratorForGitHubAction() throws {
        let response = "webhook-response-\(UUID().uuidString)"
        let stubURL = try ClaudeTestStub.makeJSONResponseScript(result: response)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let recorder = ScriptRecorder()
        let router = makeRouter(claudePath: stubURL.path, recorder: recorder)

        let payload: [String: Any] = ["action": "opened", "repo": "samara/main"]
        let event = SenseEvent(
            sense: "webhook",
            priority: .background,
            data: [
                "source": AnyCodable("github"),
                "payload": AnyCodable(payload)
            ]
        )

        router.route(event)
        router.processBackgroundQueue()

        XCTAssertEqual(recorder.scripts.count, 1)
        XCTAssertTrue(recorder.scripts[0].contains(response))

        let contents = try episodeContents()
        XCTAssertTrue(contents.contains("Sense: webhook"))
        XCTAssertTrue(contents.contains(response))
    }
}
