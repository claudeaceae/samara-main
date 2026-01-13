import XCTest

final class MailStoreTests: SamaraTestCase {

    private func makeOutput(records: [[String]]) -> String {
        let recordSep = "\u{1E}"
        let fieldSep = "\u{1F}"
        return records.map { $0.joined(separator: fieldSep) }.joined(separator: recordSep) + recordSep
    }

    func testFetchUnreadEmailsParsesOutput() throws {
        let dateStr = "Friday, December 19, 2025 at 4:52:43 PM"
        let output = makeOutput(records: [[
            "100",
            "Hello",
            "Tester <tester@example.com>",
            dateStr,
            "Body text"
        ]])

        var scripts: [String] = []
        let store = MailStore(
            targetEmails: ["tester@example.com"],
            accountName: "iCloud",
            appleScriptRunner: { script in
                scripts.append(script)
                return output
            }
        )

        let emails = try store.fetchUnreadEmails()
        XCTAssertEqual(emails.count, 1)
        XCTAssertEqual(emails[0].id, "100")
        XCTAssertEqual(emails[0].subject, "Hello")
        XCTAssertEqual(emails[0].senderName, "Tester")
        XCTAssertFalse(emails[0].isRead)
        XCTAssertTrue(emails[0].fullDescription.contains("Body text"))
        XCTAssertTrue(scripts.first?.contains("account \"iCloud\"") == true)
    }

    func testFetchRecentEmailsIncludesReadStatus() throws {
        let dateStr = "Friday, December 19, 2025 at 4:52:43 PM"
        let output = makeOutput(records: [[
            "200",
            "Recent",
            "tester@example.com",
            dateStr,
            "Recent body",
            "true"
        ]])

        let store = MailStore(
            targetEmails: ["tester@example.com"],
            accountName: nil,
            appleScriptRunner: { _ in output }
        )

        let emails = try store.fetchRecentEmails(limit: 5)
        XCTAssertEqual(emails.count, 1)
        XCTAssertEqual(emails[0].id, "200")
        XCTAssertTrue(emails[0].isRead)
    }

    func testSendReplyEscapesBodyAndSubject() throws {
        var scripts: [String] = []
        let store = MailStore(
            targetEmails: ["tester@example.com"],
            appleScriptRunner: { script in
                scripts.append(script)
                return ""
            }
        )

        try store.sendReply(
            to: "tester@example.com",
            subject: "Quote \"here\"",
            body: "Body with \\slash and \"quotes\""
        )

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("subject:\"Quote \\\"here\\\"\""))
        XCTAssertTrue(scripts[0].contains("content:\"Body with \\\\slash and \\\"quotes\\\"\""))
    }

    func testIsFromTargetMatchesSender() {
        let store = MailStore(targetEmails: ["tester@example.com"])
        let email = Email(
            id: "1",
            subject: "Hello",
            sender: "Tester <tester@example.com>",
            senderName: "Tester",
            date: Date(),
            content: "",
            isRead: false
        )

        XCTAssertTrue(store.isFromTarget(email))
    }
}
