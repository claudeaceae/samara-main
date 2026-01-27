import XCTest

final class MailWatcherTests: SamaraTestCase {

    private struct SeenIdsState: Decodable {
        let seenIds: [String]

        enum CodingKeys: String, CodingKey {
            case seenIds = "seen_ids"
        }
    }

    private func makeOutput(records: [[String]]) -> String {
        let recordSep = "\u{1E}"
        let fieldSep = "\u{1F}"
        return records.map { $0.joined(separator: fieldSep) }.joined(separator: recordSep) + recordSep
    }

    func testStartDetectsNewTargetEmail() throws {
        let dateStr = "Friday, December 19, 2025 at 4:52:43 PM"
        let output = makeOutput(records: [
            ["300", "Target", "Tester <tester@example.com>", dateStr, "Body"],
            ["301", "Other", "Other <other@example.com>", dateStr, "Body"]
        ])

        let store = MailStore(
            targetEmails: ["tester@example.com"],
            appleScriptRunner: { _ in output }
        )

        let expectation = expectation(description: "new email")
        var received: [Email] = []

        let watcher = MailWatcher(store: store, pollInterval: 0.1) { email in
            received.append(email)
            expectation.fulfill()
        }

        watcher.start()
        wait(for: [expectation], timeout: 1.0)
        watcher.stop()

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.id, "300")

        let seenPath = TestEnvironment.mindPath.appendingPathComponent("state/services/email-seen-ids.json")
        let data = try Data(contentsOf: seenPath)
        let ids = try JSONDecoder().decode(SeenIdsState.self, from: data)
        XCTAssertTrue(ids.seenIds.contains("300"))
    }

    func testPruneSeenIdsReducesCount() throws {
        let store = MailStore(targetEmails: ["tester@example.com"], appleScriptRunner: { _ in "" })
        let watcher = MailWatcher(store: store, pollInterval: 0.1) { _ in }

        watcher.markAsSeen("a")
        watcher.markAsSeen("b")
        watcher.markAsSeen("c")
        watcher.pruneSeenIds(keepCount: 2)

        let seenPath = TestEnvironment.mindPath.appendingPathComponent("state/services/email-seen-ids.json")
        let data = try Data(contentsOf: seenPath)
        let ids = try JSONDecoder().decode(SeenIdsState.self, from: data)
        XCTAssertLessThanOrEqual(ids.seenIds.count, 2)
    }
}
