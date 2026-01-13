import XCTest

final class MessageSenderTests: SamaraTestCase {
    private let targetHandle = "+15555550123"

    func testSendEscapesQuotesAndTargetsParticipant() throws {
        var scripts: [String] = []
        let sender = MessageSender(targetId: targetHandle, appleScriptRunner: { script in
            scripts.append(script)
        })

        try sender.send("He said \"hi\" and \\escape")

        XCTAssertEqual(scripts.count, 1)
        let script = scripts[0]
        XCTAssertTrue(script.contains("participant \"\(targetHandle)\""))
        XCTAssertTrue(script.contains("send \"He said \\\"hi\\\" and \\\\escape\""))
    }

    func testSendToChatUsesGroupChatSeparator() throws {
        var scripts: [String] = []
        let groupIdentifier = "ABCDEF1234567890ABCDEF1234567890"
        let sender = MessageSender(targetId: targetHandle, appleScriptRunner: { script in
            scripts.append(script)
        })

        try sender.sendToChat("Group reply", chatIdentifier: groupIdentifier)

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("chat id \"any;+;\(groupIdentifier)\""))
    }

    func testSendToChatWithEmailUsesDirectSeparator() throws {
        var scripts: [String] = []
        let emailIdentifier = "tester@example.com"
        let sender = MessageSender(targetId: targetHandle, appleScriptRunner: { script in
            scripts.append(script)
        })

        try sender.sendToChat("Hello email chat", chatIdentifier: emailIdentifier)

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("chat id \"any;-;\(emailIdentifier)\""))
    }

    func testSendSplitsLongMessageIntoChunks() throws {
        let paragraph = String(repeating: "a", count: 1800)
        let longText = "\(paragraph)\n\n\(paragraph)"

        var scripts: [String] = []
        let sender = MessageSender(targetId: targetHandle, appleScriptRunner: { script in
            scripts.append(script)
        })

        try sender.send(longText)

        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts[0].contains("send \""))
        XCTAssertTrue(scripts[1].contains("send \""))
    }

    func testSendAttachmentUsesStagingDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-message-attachments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("sample.txt")
        try "hello".write(to: sourceFile, atomically: true, encoding: .utf8)

        var scripts: [String] = []
        let sender = MessageSender(
            targetId: targetHandle,
            appleScriptRunner: { script in
                scripts.append(script)
            },
            attachmentStagingDirectory: tempDir
        )

        try sender.sendAttachment(filePath: sourceFile.path)

        XCTAssertEqual(scripts.count, 1)
        let script = scripts[0]
        XCTAssertTrue(script.contains("chat id \"any;-;\(targetHandle)\""))
        XCTAssertTrue(script.contains("POSIX file \""))
        XCTAssertTrue(script.contains(tempDir.appendingPathComponent(".imessage-send").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))

        let stagedDir = tempDir.appendingPathComponent(".imessage-send")
        let stagedContents = try FileManager.default.contentsOfDirectory(atPath: stagedDir.path)
        XCTAssertTrue(stagedContents.isEmpty)
    }
}
