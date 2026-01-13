import XCTest

final class QueueProcessorTests: SamaraTestCase {

    func testProcessesQueuedMessagesWhenUnlocked() {
        MessageQueue.clear()
        let chatId = "+15555550123"
        let scope = LockScope.conversation(chatIdentifier: chatId)
        TaskLock.release(scope: scope)

        let expectation = expectation(description: "batch ready")
        var received: [Message] = []

        let sessionManager = SessionManager(
            onBatchReady: { messages, _ in
                received = messages
                expectation.fulfill()
            },
            checkReadStatus: { _ in nil }
        )

        let processor = QueueProcessor()
        processor.setSessionManager(sessionManager)
        processor.startMonitoring()

        let message = Message(
            rowId: 101,
            text: "Queued message",
            date: Date(),
            isFromMe: false,
            handleId: chatId,
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: chatId,
            attachments: [],
            reactionType: nil,
            reactedToText: nil
        )
        MessageQueue.enqueue(message)

        DispatchQueue.global().asyncAfter(deadline: .now() + 6.0) {
            sessionManager.flush()
        }

        wait(for: [expectation], timeout: 10.0)
        processor.stopMonitoring()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.text, "Queued message")
        XCTAssertTrue(MessageQueue.isEmpty())
    }
}
