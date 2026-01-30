import XCTest

final class MessageQueueTests: SamaraTestCase {

    override func setUp() {
        super.setUp()
        // Clear the queue before each test
        MessageQueue.clear()
    }

    override func tearDown() {
        MessageQueue.clear()
        super.tearDown()
    }

    // MARK: - Helper

    private func createTestMessage(
        rowId: Int64 = 1,
        text: String = "Test message",
        chatIdentifier: String = "test-chat"
    ) -> Message {
        return Message(
            rowId: rowId,
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: "+15551234567",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: chatIdentifier,
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )
    }

    // MARK: - Basic Queue Tests

    func testEnqueue() {
        XCTAssertTrue(MessageQueue.isEmpty())
        XCTAssertEqual(MessageQueue.count(), 0)

        let message = createTestMessage()
        MessageQueue.enqueue(message)

        XCTAssertFalse(MessageQueue.isEmpty())
        XCTAssertEqual(MessageQueue.count(), 1)
    }

    func testDequeueAll() {
        let msg1 = createTestMessage(rowId: 1, text: "First")
        let msg2 = createTestMessage(rowId: 2, text: "Second")

        MessageQueue.enqueue(msg1)
        MessageQueue.enqueue(msg2)

        XCTAssertEqual(MessageQueue.count(), 2)

        let dequeued = MessageQueue.dequeueAll()

        XCTAssertEqual(dequeued.count, 2)
        XCTAssertTrue(MessageQueue.isEmpty())
        XCTAssertEqual(dequeued[0].message.text, "First")
        XCTAssertEqual(dequeued[1].message.text, "Second")
    }

    func testDequeueForChat() {
        let msg1 = createTestMessage(rowId: 1, text: "Chat A", chatIdentifier: "chat-a")
        let msg2 = createTestMessage(rowId: 2, text: "Chat B", chatIdentifier: "chat-b")
        let msg3 = createTestMessage(rowId: 3, text: "Chat A again", chatIdentifier: "chat-a")

        MessageQueue.enqueue(msg1)
        MessageQueue.enqueue(msg2)
        MessageQueue.enqueue(msg3)

        XCTAssertEqual(MessageQueue.count(), 3)

        let chatAMessages = MessageQueue.dequeue(forChat: "chat-a")

        XCTAssertEqual(chatAMessages.count, 2)
        XCTAssertEqual(MessageQueue.count(), 1)  // Only chat-b message remains
    }

    func testClear() {
        MessageQueue.enqueue(createTestMessage(rowId: 1))
        MessageQueue.enqueue(createTestMessage(rowId: 2))
        MessageQueue.enqueue(createTestMessage(rowId: 3))

        XCTAssertEqual(MessageQueue.count(), 3)

        MessageQueue.clear()

        XCTAssertTrue(MessageQueue.isEmpty())
        XCTAssertEqual(MessageQueue.count(), 0)
    }

    // MARK: - Deduplication Tests

    func testNoDuplicateEnqueue() {
        let message = createTestMessage(rowId: 42)

        MessageQueue.enqueue(message)
        MessageQueue.enqueue(message)  // Same rowId
        MessageQueue.enqueue(message)  // Same rowId again

        XCTAssertEqual(MessageQueue.count(), 1, "Should not enqueue duplicate messages")
    }

    // MARK: - Queue Overflow Tests

    func testQueueOverflow() {
        // Enqueue more than maxQueueSize messages
        for i in 1...60 {  // maxQueueSize is 50
            MessageQueue.enqueue(createTestMessage(rowId: Int64(i), text: "Message \(i)"))
        }

        XCTAssertEqual(MessageQueue.count(), 50, "Queue should be limited to maxQueueSize")

        // The oldest messages should be dropped
        let messages = MessageQueue.dequeueAll()
        XCTAssertEqual(messages.first?.message.rowId, 11, "Oldest messages should be dropped")
        XCTAssertEqual(messages.last?.message.rowId, 60, "Newest messages should be kept")
    }

    // MARK: - Queued Chats Tests

    func testQueuedChats() {
        MessageQueue.enqueue(createTestMessage(rowId: 1, chatIdentifier: "chat-a"))
        MessageQueue.enqueue(createTestMessage(rowId: 2, chatIdentifier: "chat-b"))
        MessageQueue.enqueue(createTestMessage(rowId: 3, chatIdentifier: "chat-a"))
        MessageQueue.enqueue(createTestMessage(rowId: 4, chatIdentifier: "chat-c"))

        let chats = MessageQueue.queuedChats()

        XCTAssertEqual(chats.count, 3)
        XCTAssertTrue(chats.contains("chat-a"))
        XCTAssertTrue(chats.contains("chat-b"))
        XCTAssertTrue(chats.contains("chat-c"))
    }

    // MARK: - Acknowledgment Tests

    func testAcknowledgedFlag() {
        let message = createTestMessage()
        MessageQueue.enqueue(message, acknowledged: true)

        let dequeued = MessageQueue.dequeueAll()

        XCTAssertEqual(dequeued.count, 1)
        XCTAssertTrue(dequeued[0].acknowledged)
    }

    func testNotAcknowledgedByDefault() {
        let message = createTestMessage()
        MessageQueue.enqueue(message)

        let dequeued = MessageQueue.dequeueAll()

        XCTAssertEqual(dequeued.count, 1)
        XCTAssertFalse(dequeued[0].acknowledged)
    }

    // MARK: - Persistence Tests

    func testPersistenceAcrossClears() {
        // This tests that after clear + re-enqueue, data is consistent
        MessageQueue.enqueue(createTestMessage(rowId: 1, text: "First round"))
        MessageQueue.clear()

        MessageQueue.enqueue(createTestMessage(rowId: 2, text: "Second round"))

        let messages = MessageQueue.dequeueAll()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].message.text, "Second round")
    }

    // MARK: - Thread Safety (Basic)

    func testConcurrentEnqueue() {
        let expectation = XCTestExpectation(description: "Concurrent enqueue")
        let group = DispatchGroup()

        for i in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                MessageQueue.enqueue(self.createTestMessage(rowId: Int64(i), text: "Concurrent \(i)"))
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Should have all messages (no duplicates since rowIds are unique)
            XCTAssertEqual(MessageQueue.count(), 20)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
