import XCTest

final class TaskRouterTests: SamaraTestCase {

    private func makeMessage(text: String, chatIdentifier: String = "chat") -> Message {
        Message(
            rowId: Int64.random(in: 1...9999),
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: "+15551234567",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: chatIdentifier,
            attachments: [],
            reactionType: nil,
            reactedToText: nil
        )
    }

    func testClassifyBatchGroupsConversationAndSpecialTasks() {
        let router = TaskRouter()
        let messages = [
            makeMessage(text: "Hello"),
            makeMessage(text: "show webcam"),
            makeMessage(text: "https://example.com"),
            makeMessage(text: "/skill run"),
            makeMessage(text: "Another normal message")
        ]

        let tasks = router.classifyBatch(messages)

        XCTAssertEqual(tasks.count, 4)
        XCTAssertEqual(tasks[0].type, .conversation)
        XCTAssertEqual(tasks[0].messages.count, 2)
        XCTAssertEqual(tasks[1].type, .webcamCapture)
        XCTAssertEqual(tasks[2].type, .webFetch)
        XCTAssertEqual(tasks[3].type, .skillInvocation)
    }

    func testShouldIsolateTasks() {
        let router = TaskRouter()
        let conversation = [makeMessage(text: "Hello"), makeMessage(text: "How are you?")]
        XCTAssertFalse(router.shouldIsolateTasks(conversation))

        let mixed = [makeMessage(text: "Hello"), makeMessage(text: "https://example.com")]
        XCTAssertTrue(router.shouldIsolateTasks(mixed))
    }

    func testAssembleResponses() {
        let router = TaskRouter()
        let single = router.assembleResponses([(.conversation, "One")])
        XCTAssertEqual(single, "One")

        let combined = router.assembleResponses([(.conversation, "A"), (.webFetch, "B")])
        XCTAssertEqual(combined, "A\n\nB")
    }
}
