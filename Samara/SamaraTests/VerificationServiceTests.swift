import XCTest

final class VerificationServiceTests: SamaraTestCase {

    private func checklistsPath() -> String {
        TestEnvironment.installIfNeeded()
        return TestEnvironment.mindPath
            .appendingPathComponent("state/checklists")
            .path
    }

    private func makeService() -> VerificationService {
        TestEnvironment.installIfNeeded()
        let invoker = LocalModelInvoker(endpoint: URL(string: "http://localhost:11434")!, timeout: 0.1)
        return VerificationService(localInvoker: invoker, checklistsDir: checklistsPath())
    }

    private func writeChecklist(_ checklist: VerificationService.Checklist) {
        TestEnvironment.installIfNeeded()
        let checklistsURL = URL(fileURLWithPath: checklistsPath())
        try? FileManager.default.removeItem(at: checklistsURL)
        try? FileManager.default.createDirectory(at: checklistsURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try? encoder.encode(checklist)
        let fileURL = checklistsURL.appendingPathComponent("\(checklist.domain).json")
        try? data?.write(to: fileURL, options: .atomic)
    }

    func testVerifySafetyDetectsIssues() async {
        let service = makeService()
        let result = await service.verify(
            content: "rm -rf /",
            type: .safetyCheck,
            useLocalModel: false
        )

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.message.contains("Safety"))
        XCTAssertNotNil(result.details)
    }

    func testVerifyFormatDetectsWhitespace() async {
        let service = makeService()
        let result = await service.verify(
            content: "let x = 1 \n\tindent",
            type: .formatCheck,
            useLocalModel: false
        )

        XCTAssertFalse(result.passed)
        XCTAssertNotNil(result.details)
    }

    func testVerifyCustomSkipsWithoutLocalModel() async {
        let service = makeService()
        let result = await service.verify(
            content: "anything",
            type: .custom(prompt: "Check"),
            useLocalModel: false
        )

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.message.contains("skipped"))
    }

    func testRunChecklistPatternAndCommand() async {
        let checklist = VerificationService.Checklist(
            id: "custom",
            name: "Custom",
            domain: "custom",
            items: [
                VerificationService.ChecklistItem(
                    id: "pattern",
                    description: "Find needle",
                    pattern: "needle",
                    command: nil,
                    expectedOutput: nil,
                    severity: .info
                ),
                VerificationService.ChecklistItem(
                    id: "command",
                    description: "Echo pass",
                    pattern: nil,
                    command: "printf 'hello'",
                    expectedOutput: "hello",
                    severity: .info
                )
            ]
        )
        writeChecklist(checklist)

        let service = makeService()
        let results = await service.runChecklist(domain: "custom", context: "needle in hay")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.passed })
    }
}
