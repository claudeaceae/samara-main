import XCTest

final class LedgerManagerTests: SamaraTestCase {

    private func makeBaseDir() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private func ledgerFilePath(baseDir: URL, chatId: String) -> URL {
        let sanitized = chatId.replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "@", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return baseDir.appendingPathComponent("ledgers/\(sanitized).json")
    }

    func testLedgerUpdatesAndHandoffLifecycle() throws {
        let baseDir = try makeBaseDir()
        let manager = LedgerManager(baseDir: baseDir.path)

        let chatId = "user+test@example.com"
        let sessionId = "session-123"

        var ledger = manager.getLedger(forChat: chatId, sessionId: sessionId)
        XCTAssertEqual(ledger.sessionId, sessionId)
        XCTAssertEqual(ledger.chatId, chatId)

        manager.addGoal(chatId: chatId, description: "Ship tests", status: .pending, progress: "0%")
        manager.updateGoalStatus(chatId: chatId, goalIndex: 0, status: .completed, progress: "done")
        manager.recordDecision(chatId: chatId, description: "Add unit tests", rationale: "Increase coverage")
        manager.recordFileChange(chatId: chatId, path: "Samara/SamaraTests", action: .modified, summary: "New coverage")
        manager.addNextSteps(chatId: chatId, steps: ["Run suite"])
        manager.addOpenQuestions(chatId: chatId, questions: ["Any flaky cases?"])
        manager.updateContextPercentage(chatId: chatId, percentage: 0.42)
        manager.setSummary(chatId: chatId, summary: "All good")

        ledger = manager.getLedger(forChat: chatId, sessionId: sessionId)
        XCTAssertEqual(ledger.activeGoals.count, 1)
        XCTAssertEqual(ledger.activeGoals.first?.status, .completed)
        XCTAssertEqual(ledger.decisions.count, 1)
        XCTAssertEqual(ledger.filesModified.count, 1)
        XCTAssertEqual(ledger.nextSteps.count, 1)
        XCTAssertEqual(ledger.openQuestions.count, 1)
        XCTAssertEqual(ledger.contextPercentage, 0.42, accuracy: 0.0001)
        XCTAssertEqual(ledger.summary, "All good")

        let ledgerPath = ledgerFilePath(baseDir: baseDir, chatId: chatId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ledgerPath.path))

        let handoff = manager.createHandoff(forChat: chatId, reason: .contextThreshold)
        XCTAssertNotNil(handoff)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerPath.path))

        let recent = manager.getMostRecentHandoff(forChat: chatId)
        XCTAssertNotNil(recent)

        if let handoff = handoff {
            let context = manager.contextFromHandoff(handoff)
            XCTAssertTrue(context.contains("context_threshold"))
            XCTAssertTrue(context.contains("Session: \(sessionId)"))
        }
    }

    func testHumanReadableSummaryIncludesSections() throws {
        let now = Date()
        let ledger = LedgerManager.Ledger(
            sessionId: "session-xyz",
            chatId: "chat-abc",
            startedAt: now,
            lastUpdated: now,
            activeGoals: [
                .init(description: "Write docs", status: .inProgress, progress: "halfway")
            ],
            decisions: [
                .init(description: "Use fixtures", rationale: "Stable tests", timestamp: now)
            ],
            filesModified: [
                .init(path: "Samara/SamaraTests", action: .modified, summary: "Added tests")
            ],
            nextSteps: ["Run suite"],
            openQuestions: ["Any gaps?"],
            contextPercentage: 0.5,
            summary: "Checkpoint"
        )

        let text = ledger.humanReadable()
        XCTAssertTrue(text.contains("# Session Ledger"))
        XCTAssertTrue(text.contains("Session: session-xyz"))
        XCTAssertTrue(text.contains("Context Usage: 50%"))
        XCTAssertTrue(text.contains("## Summary"))
        XCTAssertTrue(text.contains("## Active Goals"))
        XCTAssertTrue(text.contains("## Key Decisions"))
        XCTAssertTrue(text.contains("## Files Changed"))
        XCTAssertTrue(text.contains("## Next Steps"))
        XCTAssertTrue(text.contains("## Open Questions"))
    }
}
