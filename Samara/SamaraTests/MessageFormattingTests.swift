import XCTest

final class MessageFormattingTests: SamaraTestCase {
    func testFullDescriptionFiltersReplacementCharactersAndDataURIs() {
        let base64Payload = String(repeating: "A", count: 120)
        let text = "hello ￼ data:image/png;base64,\(base64Payload) world"
        let message = Message(
            rowId: 1,
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )

        let description = message.fullDescription
        XCTAssertFalse(description.contains("￼"))
        XCTAssertTrue(description.contains("hello"))
        XCTAssertTrue(description.contains("Embedded image/png content"))
        XCTAssertFalse(description.contains("data:image/png;base64"))
    }

    func testFullDescriptionSkipsOnlyReplacementCharacters() {
        let message = Message(
            rowId: 2,
            text: "￼￼",
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )

        XCTAssertEqual(message.fullDescription, "")
    }

    func testFullDescriptionWithSenderPrefixesOnlyNonCollaboratorInGroup() {
        let collaborator = "+15555550123"
        let otherHandle = "+15555550999"
        let baseMessage = Message(
            rowId: 3,
            text: "Group update",
            date: Date(),
            isFromMe: false,
            handleId: collaborator,
            chatId: 2,
            isGroupChat: true,
            chatIdentifier: "ABCDEF1234567890ABCDEF1234567890",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )

        let fromCollaborator = baseMessage.fullDescriptionWithSender(targetHandles: [collaborator])
        XCTAssertEqual(fromCollaborator, baseMessage.fullDescription)

        let otherMessage = Message(
            rowId: 4,
            text: "Hello from someone else",
            date: Date(),
            isFromMe: false,
            handleId: otherHandle,
            chatId: 2,
            isGroupChat: true,
            chatIdentifier: "ABCDEF1234567890ABCDEF1234567890",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )

        let fromOther = otherMessage.fullDescriptionWithSender(targetHandles: [collaborator])
        XCTAssertTrue(fromOther.hasPrefix("[\(otherHandle)]:"))
    }

    func testFullDescriptionIncludesReplyContext() {
        let message = Message(
            rowId: 5,
            text: "This is my reply",
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: "Original message here"
        )

        let description = message.fullDescription
        XCTAssertTrue(description.contains("[Replying to: \"Original message here\"]"))
        XCTAssertTrue(description.contains("This is my reply"))
    }

    func testFullDescriptionTruncatesLongReplyContext() {
        let longOriginal = String(repeating: "x", count: 120)
        let message = Message(
            rowId: 6,
            text: "Short reply",
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: longOriginal
        )

        let description = message.fullDescription
        // Should truncate to 100 chars + "..."
        XCTAssertTrue(description.contains("..."))
        XCTAssertFalse(description.contains(longOriginal))
        let expectedTruncated = String(repeating: "x", count: 100)
        XCTAssertTrue(description.contains(expectedTruncated))
    }

    func testIsReplyProperty() {
        let replyMessage = Message(
            rowId: 7,
            text: "Reply text",
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: "Original"
        )
        XCTAssertTrue(replyMessage.isReply)

        let regularMessage = Message(
            rowId: 8,
            text: "Regular text",
            date: Date(),
            isFromMe: false,
            handleId: "+15555550123",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "+15555550123",
            attachments: [],
            reactionType: nil,
            reactedToText: nil,
            replyToText: nil
        )
        XCTAssertFalse(regularMessage.isReply)
    }
}
