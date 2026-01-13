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
            reactedToText: nil
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
            reactedToText: nil
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
            reactedToText: nil
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
            reactedToText: nil
        )

        let fromOther = otherMessage.fullDescriptionWithSender(targetHandles: [collaborator])
        XCTAssertTrue(fromOther.hasPrefix("[\(otherHandle)]:"))
    }
}
