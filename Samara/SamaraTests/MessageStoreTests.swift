import XCTest

final class MessageStoreTests: SamaraTestCase {
    func testFetchNewMessagesIncludesGroupAndDirect() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        let messages = try store.fetchNewMessages(since: 0)
        XCTAssertEqual(messages.count, 6)

        let directMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.directMessageRowId })
        XCTAssertFalse(directMessage.isGroupChat)
        XCTAssertEqual(directMessage.chatIdentifier, fixture.directChatIdentifier)
        XCTAssertEqual(directMessage.handleId, fixture.collaboratorHandle)
        XCTAssertEqual(directMessage.text, "Hello from E")
        XCTAssertEqual(directMessage.date.timeIntervalSinceReferenceDate,
                       fixture.directMessageDate.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)

        let groupMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.groupMessageRowId })
        XCTAssertTrue(groupMessage.isGroupChat)
        XCTAssertEqual(groupMessage.chatIdentifier, fixture.groupChatIdentifier)
        XCTAssertEqual(groupMessage.handleId, fixture.otherHandle)
        let groupDescription = groupMessage.fullDescriptionWithSender(targetHandles: [fixture.collaboratorHandle])
        XCTAssertTrue(groupDescription.contains("[\(fixture.otherHandle)]: Group hello"))

        let reactionMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.reactionRowId })
        XCTAssertTrue(reactionMessage.isReaction)
        XCTAssertEqual(reactionMessage.reactionType, .liked)
        XCTAssertEqual(reactionMessage.reactedToText, "Group hello")
        XCTAssertTrue(reactionMessage.fullDescription.contains("reacted with"))

        let attachmentMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.attachmentMessageRowId })
        XCTAssertTrue(attachmentMessage.hasAttachments)
        XCTAssertEqual(attachmentMessage.attachments.count, 1)
        let attachment = attachmentMessage.attachments[0]
        XCTAssertEqual(attachment.fileName, fixture.attachmentTransferName)
        XCTAssertTrue(attachment.filePath.contains("/Pictures/test.png"))
        XCTAssertTrue(attachmentMessage.fullDescription.contains("[Image:"))

        let replyMessage = try XCTUnwrap(messages.first { $0.rowId == fixture.replyMessageRowId })
        XCTAssertTrue(replyMessage.isReply)
        XCTAssertEqual(replyMessage.replyToText, "Hello from E")
        XCTAssertEqual(replyMessage.text, "This is my reply")
        XCTAssertTrue(replyMessage.fullDescription.contains("[Replying to:"))

        // Test reply to attachment-only message
        let replyToAttachment = try XCTUnwrap(messages.first { $0.rowId == fixture.replyToAttachmentRowId })
        XCTAssertTrue(replyToAttachment.isReply)
        XCTAssertEqual(replyToAttachment.replyToText, "[Image]")
        XCTAssertEqual(replyToAttachment.text, "Nice photo!")
        XCTAssertTrue(replyToAttachment.fullDescription.contains("[Replying to: \"[Image]\"]"))
    }

    func testFetchChatInfo() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        let info = store.fetchChatInfo(chatId: fixture.groupChatId)
        XCTAssertEqual(info.displayName, "Test Group")
        XCTAssertEqual(Set(info.participants), Set([fixture.collaboratorHandle, fixture.otherHandle]))
    }

    func testReadStatusAndLastOutgoingRowId() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        let status = store.getReadStatus(forRowId: fixture.outgoingMessageRowId)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.isRead, true)
        XCTAssertNotNil(status?.readTime)

        let lastOutgoing = store.getLastOutgoingMessageRowId()
        XCTAssertEqual(lastOutgoing, fixture.outgoingMessageRowId)
    }
}
