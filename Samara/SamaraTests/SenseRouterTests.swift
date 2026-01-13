import XCTest

final class SenseRouterTests: SamaraTestCase {

    private final class ScriptRecorder {
        var scripts: [String] = []
    }

    private func makeRouter(recorder: ScriptRecorder, onSend: (() -> Void)? = nil) -> SenseRouter {
        let sender = MessageSender(
            targetId: "tester@example.com",
            appleScriptRunner: { script in
                recorder.scripts.append(script)
                onSend?()
            }
        )
        let episodeLogger = EpisodeLogger()
        let messageBus = MessageBus(sender: sender, episodeLogger: episodeLogger, collaboratorName: "Tester")
        let memoryContext = MemoryContext()
        let invoker = ClaudeInvoker(claudePath: "/usr/bin/true", timeout: 1, memoryContext: memoryContext, useFallbackChain: false)

        return SenseRouter(
            invoker: invoker,
            memoryContext: memoryContext,
            episodeLogger: episodeLogger,
            messageBus: messageBus,
            collaboratorName: "Tester"
        )
    }

    func testRouteTestEventSendsMessage() {
        let expectation = expectation(description: "send")
        let recorder = ScriptRecorder()

        let router = makeRouter(recorder: recorder) {
            expectation.fulfill()
        }

        let event = SenseEvent(
            sense: "test",
            priority: .normal,
            data: ["msg": AnyCodable("hello")]
        )

        router.route(event)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(recorder.scripts.count, 1)
        XCTAssertTrue(recorder.scripts[0].contains("Test sense event received: hello"))
    }

    func testLocationBackgroundEventLogsWithoutSend() throws {
        let recorder = ScriptRecorder()
        let router = makeRouter(recorder: recorder)

        let event = SenseEvent(
            sense: "location",
            priority: .background,
            data: ["lat": AnyCodable(40.0)]
        )

        router.route(event)
        router.processBackgroundQueue()

        XCTAssertTrue(recorder.scripts.isEmpty)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let episodePath = TestEnvironment.mindPath
            .appendingPathComponent("memory/episodes/\(today).md")

        let contents = try String(contentsOf: episodePath, encoding: .utf8)
        XCTAssertTrue(contents.contains("Sense:location"))
    }

    func testRegisterHandlerOverridesDefault() {
        let recorder = ScriptRecorder()
        let router = makeRouter(recorder: recorder)
        var handledSense: String?

        router.registerHandler(forSense: "custom") { event in
            handledSense = event.sense
        }

        let event = SenseEvent(sense: "custom", priority: .background)
        router.route(event)
        router.processBackgroundQueue()

        XCTAssertEqual(handledSense, "custom")
        XCTAssertTrue(recorder.scripts.isEmpty)
    }
}
