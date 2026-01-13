import XCTest

final class MessageBusTests: SamaraTestCase {
    func testSendLogsOutboundMessage() throws {
        var scripts: [String] = []
        let sender = MessageSender(targetId: "+15555550123", appleScriptRunner: { script in
            scripts.append(script)
        })
        let logger = EpisodeLogger()
        let bus = MessageBus(sender: sender, episodeLogger: logger, collaboratorName: "Tester")

        try bus.send("Hello from bus", type: .conversationResponse)

        XCTAssertEqual(scripts.count, 1)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let episodePath = MindPaths.mindPath("memory/episodes/\(dateString).md")
        let contents = try String(contentsOfFile: episodePath, encoding: .utf8)
        XCTAssertTrue(contents.contains("**Claude:** Hello from bus"))
        XCTAssertTrue(contents.contains("[iMessage]"))
    }
}
