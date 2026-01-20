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

    private func sanitizeChatId(_ chatId: String) -> String {
        chatId
            .replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func ledgerFileURL(for chatId: String) -> URL {
        let sanitized = sanitizeChatId(chatId)
        return TestEnvironment.mindPath.appendingPathComponent("state/ledgers/\(sanitized).json")
    }

    private func handoffFiles(for chatId: String) -> [URL] {
        let sanitized = sanitizeChatId(chatId)
        let handoffsURL = TestEnvironment.mindPath.appendingPathComponent("state/handoffs")
        guard let files = try? FileManager.default.contentsOfDirectory(at: handoffsURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.lastPathComponent.contains(sanitized) }
    }

    private func cleanLedgerState(for chatId: String) {
        let ledgerURL = ledgerFileURL(for: chatId)
        try? FileManager.default.removeItem(at: ledgerURL)
        for fileURL in handoffFiles(for: chatId) {
            try? FileManager.default.removeItem(at: fileURL)
        }
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

    func testInvokeBatchAppliesLedgerUpdatesFromStructuredOutput() throws {
        let chatId = "ledger-chat-1"
        cleanLedgerState(for: chatId)

        let structuredOutput: [String: Any] = [
            "message": "All set",
            "ledger": [
                "summary": "Wrapped up ledger updates",
                "goals": [
                    ["description": "Ship ledger wiring", "status": "in_progress", "progress": "halfway"]
                ],
                "decisions": [
                    ["description": "Use structured output", "rationale": "Deterministic parsing"]
                ],
                "next_steps": ["Add handoff test"],
                "open_questions": ["Any edge cases left?"]
            ]
        ]

        let payload: [String: Any] = [
            "structured_output": structuredOutput,
            "session_id": "session-ledger"
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let body = """
        cat <<'EOF'
        \(jsonString)
        EOF
        """
        let stubURL = try ClaudeTestStub.makeScript(body: body)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)
        let message = makeMessage(text: "hi", chatIdentifier: chatId)

        let result = try invoker.invokeBatch(messages: [message], context: "context")
        XCTAssertEqual(result.response, "All set")

        let ledgerURL = ledgerFileURL(for: chatId)
        let data = try Data(contentsOf: ledgerURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ledger = try decoder.decode(LedgerManager.Ledger.self, from: data)

        XCTAssertEqual(ledger.sessionId, "session-ledger")
        XCTAssertEqual(ledger.summary, "Wrapped up ledger updates")
        XCTAssertEqual(ledger.activeGoals.first?.description, "Ship ledger wiring")
        XCTAssertEqual(ledger.activeGoals.first?.status, .inProgress)
        XCTAssertEqual(ledger.activeGoals.first?.progress, "halfway")
        XCTAssertEqual(ledger.decisions.first?.description, "Use structured output")
        XCTAssertEqual(ledger.decisions.first?.rationale, "Deterministic parsing")
        XCTAssertEqual(ledger.nextSteps.first, "Add handoff test")
        XCTAssertEqual(ledger.openQuestions.first, "Any edge cases left?")
    }

    func testInvokeBatchCreatesHandoffFromStructuredOutput() throws {
        let chatId = "ledger-chat-2"
        cleanLedgerState(for: chatId)

        let structuredOutput: [String: Any] = [
            "message": "Wrapping up",
            "ledger": [
                "summary": "Context is near full",
                "handoff_reason": "context_threshold"
            ]
        ]
        let payload: [String: Any] = [
            "structured_output": structuredOutput,
            "session_id": "session-handoff"
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let body = """
        cat <<'EOF'
        \(jsonString)
        EOF
        """
        let stubURL = try ClaudeTestStub.makeScript(body: body)
        defer { ClaudeTestStub.cleanup(stubURL) }

        let invoker = makeInvoker(claudePath: stubURL.path)
        let message = makeMessage(text: "hi", chatIdentifier: chatId)

        _ = try invoker.invokeBatch(messages: [message], context: "context")

        let ledgerURL = ledgerFileURL(for: chatId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path))

        let handoffFiles = handoffFiles(for: chatId)
        XCTAssertFalse(handoffFiles.isEmpty)

        let data = try Data(contentsOf: handoffFiles[0])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let handoff = try decoder.decode(LedgerManager.Handoff.self, from: data)
        XCTAssertEqual(handoff.reason, .contextThreshold)
        XCTAssertEqual(handoff.ledger.sessionId, "session-handoff")
    }
}
