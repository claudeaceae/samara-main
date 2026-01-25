import XCTest

final class ContextSelectorTests: SamaraTestCase {
    private func ensureMindFile(_ relativePath: String, contents: String) throws {
        let url = TestEnvironment.mindPath.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeSelector(smartContext: Bool) -> ContextSelector {
        ContextSelector(
            memoryContext: MemoryContext(),
            contextRouter: ContextRouter(enabled: false),
            features: Configuration.FeaturesConfig(smartContext: smartContext, smartContextTimeout: 1.0)
        )
    }

    func testSmartContextIncludesCoreHeading() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nSmart context identity.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Keep context lean.\n")

        let selector = makeSelector(smartContext: true)

        let context = selector.context(forText: "Just testing", isCollaboratorChat: true)
        XCTAssertTrue(context.contains("## Current Time"))
        XCTAssertTrue(context.contains("## Available Resources"))
        XCTAssertFalse(context.contains("### Identity"))
    }

    func testLegacyContextKeepsIdentitySection() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nLegacy context identity.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Keep context lean.\n")

        let selector = makeSelector(smartContext: false)

        let context = selector.context(forText: "Just testing", isCollaboratorChat: true)
        XCTAssertTrue(context.contains("### Identity"))
        XCTAssertFalse(context.contains("## Current Time"))
    }

    func testSmartContextForIMessagesUsesSmartContext() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nSmart context identity.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Keep context lean.\n")

        let selector = makeSelector(smartContext: true)
        let message = Message(
            rowId: 1,
            text: "Hello from chat",
            date: Date(),
            isFromMe: false,
            handleId: "tester@example.com",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: "chat-1",
            attachments: [],
            reactionType: nil,
            reactedToText: nil
        )

        let context = selector.context(for: [message], isCollaboratorChat: true)
        XCTAssertTrue(context.contains("## Current Time"))
        XCTAssertTrue(context.contains("## Available Resources"))
        XCTAssertFalse(context.contains("### Identity"))
    }

    func testSmartContextForEmailFlowUsesSmartContext() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nSmart context identity.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Keep context lean.\n")

        let selector = makeSelector(smartContext: true)
        let emailText = """
        Email from tester@example.com
        Subject: Quick check
        Just making sure smart context is used.
        """

        let context = selector.context(
            forText: emailText,
            isCollaboratorChat: true,
            handleId: "tester@example.com",
            chatIdentifier: "tester@example.com"
        )
        XCTAssertTrue(context.contains("## Current Time"))
        XCTAssertTrue(context.contains("## Available Resources"))
        XCTAssertFalse(context.contains("### Identity"))
    }

    func testSmartContextForScratchpadFlowUsesSmartContext() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nSmart context identity.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Keep context lean.\n")

        let selector = makeSelector(smartContext: true)
        let scratchpadText = "Scratchpad update: keep testing smart context."

        let context = selector.context(
            forText: scratchpadText,
            isCollaboratorChat: true,
            handleId: "tester@example.com",
            chatIdentifier: "tester@example.com"
        )
        XCTAssertTrue(context.contains("## Current Time"))
        XCTAssertTrue(context.contains("## Available Resources"))
        XCTAssertFalse(context.contains("### Identity"))
    }
}
