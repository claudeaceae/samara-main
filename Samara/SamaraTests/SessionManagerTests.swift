import XCTest

final class SessionManagerTests: SamaraTestCase {

    var sessionManager: SessionManager!
    var batchReadyMessages: [Message]?
    var batchReadySessionId: String?
    var expiredSessionId: String?
    var expiredMessages: [Message]?

    override func setUp() {
        super.setUp()
        batchReadyMessages = nil
        batchReadySessionId = nil
        expiredSessionId = nil
        expiredMessages = nil

        sessionManager = SessionManager(
            onBatchReady: { [weak self] messages, sessionId in
                self?.batchReadyMessages = messages
                self?.batchReadySessionId = sessionId
            },
            checkReadStatus: { _ in nil },
            onSessionExpired: { [weak self] sessionId, messages in
                self?.expiredSessionId = sessionId
                self?.expiredMessages = messages
            }
        )
    }

    override func tearDown() {
        sessionManager = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func createTestMessage(
        rowId: Int64 = 1,
        text: String = "Test message",
        chatIdentifier: String = "test-chat",
        isGroupChat: Bool = false
    ) -> Message {
        return Message(
            rowId: rowId,
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: "+15551234567",
            chatId: 1,
            isGroupChat: isGroupChat,
            chatIdentifier: chatIdentifier,
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )
    }

    // MARK: - Basic Message Buffering

    func testAddMessage() {
        let message = createTestMessage()
        sessionManager.addMessage(message)

        // Message should be buffered, not immediately processed
        XCTAssertNil(batchReadyMessages, "Message should be buffered, not immediately processed")
    }

    func testFlush() {
        let msg1 = createTestMessage(rowId: 1, text: "First")
        let msg2 = createTestMessage(rowId: 2, text: "Second")

        sessionManager.addMessage(msg1)
        sessionManager.addMessage(msg2)

        sessionManager.flush()

        XCTAssertNotNil(batchReadyMessages)
        XCTAssertEqual(batchReadyMessages?.count, 2)
        XCTAssertEqual(batchReadyMessages?[0].text, "First")
        XCTAssertEqual(batchReadyMessages?[1].text, "Second")
    }

    // MARK: - Session Recording

    func testRecordResponse() {
        let chatId = "test-chat-123"

        // Record a response
        sessionManager.recordResponse(
            sessionId: "session-abc",
            responseRowId: 100,
            forChat: chatId
        )

        // Should be able to get the session ID
        let sessionId = sessionManager.getCurrentSessionId(forChat: chatId)
        XCTAssertEqual(sessionId, "session-abc")
    }

    func testClearSession() {
        let chatId = "test-chat-123"

        sessionManager.recordResponse(
            sessionId: "session-abc",
            responseRowId: 100,
            forChat: chatId
        )

        sessionManager.clearSession(forChat: chatId)

        let sessionId = sessionManager.getCurrentSessionId(forChat: chatId)
        XCTAssertNil(sessionId)
    }

    // MARK: - Multi-Chat Isolation

    func testMultipleChatsSeparateBuffers() {
        let chatA = "chat-a"
        let chatB = "chat-b"

        sessionManager.addMessage(createTestMessage(rowId: 1, chatIdentifier: chatA))
        sessionManager.addMessage(createTestMessage(rowId: 2, chatIdentifier: chatB))
        sessionManager.addMessage(createTestMessage(rowId: 3, chatIdentifier: chatA))

        // Flush should process all chats
        sessionManager.flush()

        // All messages should be processed (grouped by chat internally)
        XCTAssertNotNil(batchReadyMessages)
    }

    func testMultipleChatsSeparateSessions() {
        let chatA = "chat-a"
        let chatB = "chat-b"

        sessionManager.recordResponse(sessionId: "session-a", responseRowId: 1, forChat: chatA)
        sessionManager.recordResponse(sessionId: "session-b", responseRowId: 2, forChat: chatB)

        XCTAssertEqual(sessionManager.getCurrentSessionId(forChat: chatA), "session-a")
        XCTAssertEqual(sessionManager.getCurrentSessionId(forChat: chatB), "session-b")

        // Clearing one shouldn't affect the other
        sessionManager.clearSession(forChat: chatA)
        XCTAssertNil(sessionManager.getCurrentSessionId(forChat: chatA))
        XCTAssertEqual(sessionManager.getCurrentSessionId(forChat: chatB), "session-b")
    }

    // MARK: - Session Expiration with Distillation

    func testClearSessionTriggersDistillation() {
        let chatId = "test-chat"

        // Add some messages, flush to process them, then record session
        sessionManager.addMessage(createTestMessage(rowId: 1, chatIdentifier: chatId))
        sessionManager.flush()  // This moves messages into session tracking

        // Record the session response
        sessionManager.recordResponse(sessionId: "session-123", responseRowId: 10, forChat: chatId)

        // Add more messages and flush
        sessionManager.addMessage(createTestMessage(rowId: 2, chatIdentifier: chatId))
        sessionManager.flush()  // This also adds to session tracking

        // Clear with distillation trigger
        sessionManager.clearSession(forChat: chatId, triggerDistillation: true)

        // Session expired callback should have been called
        XCTAssertEqual(expiredSessionId, "session-123")
        XCTAssertNotNil(expiredMessages)
        XCTAssertEqual(expiredMessages?.count, 2)
    }

    // MARK: - Empty States

    func testFlushWithNoMessages() {
        sessionManager.flush()

        // Should not crash and should not call onBatchReady
        XCTAssertNil(batchReadyMessages)
    }

    func testGetSessionIdForUnknownChat() {
        let sessionId = sessionManager.getCurrentSessionId(forChat: "unknown-chat")
        XCTAssertNil(sessionId)
    }

    func testClearSessionForUnknownChat() {
        // Should not crash
        sessionManager.clearSession(forChat: "unknown-chat")
    }
}
