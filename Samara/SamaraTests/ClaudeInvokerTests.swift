import XCTest

final class ClaudeInvokerTests: SamaraTestCase {

    private func makeInvoker(claudePath: String) -> ClaudeInvoker {
        ClaudeInvoker(
            claudePath: claudePath,
            timeout: 2,
            memoryContext: MemoryContext(),
            useFallbackChain: false
        )
    }

    private func makeMessage(text: String, chatIdentifier: String = "chat-1") -> Message {
        Message(
            rowId: 1,
            text: text,
            date: Date(),
            isFromMe: false,
            handleId: "tester@example.com",
            chatId: 1,
            isGroupChat: false,
            chatIdentifier: chatIdentifier,
            attachments: [],
            reactionType: nil,
            reactedToText: nil
        )
    }

    func testInvokeBatchParsesJsonAndSanitizesResponse() throws {
        let stubURL = try ClaudeTestStub.makeJSONResponseScript(
            result: "<thinking>secret</thinking>Hello",
            sessionId: "session-123"
        )
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)
        let message = makeMessage(text: "hi")

        let result = try invoker.invokeBatch(messages: [message], context: "context")

        XCTAssertEqual(result.response, "Hello")
        XCTAssertEqual(result.sessionId, "session-123")
    }

    func testInvokeBatchRetriesWhenSessionMissing() throws {
        let body = """
        if echo "$@" | grep -q -- "--resume"; then
          echo "No conversation found with session ID: 123"
          exit 0
        fi
        cat <<'EOF'
        {"result":"fresh response","session_id":"fresh-session"}
        EOF
        """
        let stubURL = try ClaudeTestStub.makeScript(body: body)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)
        let message = makeMessage(text: "hi")

        let result = try invoker.invokeBatch(messages: [message], context: "context", resumeSessionId: "stale-session")

        XCTAssertEqual(result.response, "fresh response")
        XCTAssertEqual(result.sessionId, "fresh-session")
    }

    func testInvokeReturnsProcessingErrorWhenResultMissing() throws {
        let body = """
        cat <<'EOF'
        {"session_id":"abc"}
        EOF
        """
        let stubURL = try ClaudeTestStub.makeScript(body: body)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)
        let response = try invoker.invoke(prompt: "hello", context: "context")

        XCTAssertEqual(response, "[Processing error - please try again]")
    }

    func testInvokeThrowsForErrorJson() throws {
        let body = """
        cat <<'EOF'
        {"is_error":true,"result":"Prompt is too long"}
        EOF
        """
        let stubURL = try ClaudeTestStub.makeScript(body: body)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)

        XCTAssertThrowsError(try invoker.invoke(prompt: "hello", context: "context")) { error in
            guard case ClaudeInvokerError.executionFailed(_, let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Prompt is too long"))
        }
    }
}
