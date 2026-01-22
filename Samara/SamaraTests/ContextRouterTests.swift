import XCTest

final class ContextRouterTests: SamaraTestCase {
    private func makeMessage(text: String) -> Message {
        Message(
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
    }

    func testAnalyzeParsesWrappedResultObject() throws {
        let output = """
        {"result":{"isActionRelated":true,"referencesHistory":false,"mentionedPeople":["Alice"],"isLocationRelated":false,"isScheduleRelated":true,"searchTerms":["roadmap"],"isSimpleGreeting":false,"needsRecentContext":true,"needsLearnings":true,"needsObservations":false}}
        """
        let router = ContextRouter(
            claudePath: "/missing/claude",
            timeout: 1.0,
            enabled: true,
            outputProvider: { _ in output }
        )
        let needs = router.analyze([makeMessage(text: "Can you check the calendar with Alice?")])

        XCTAssertTrue(needs.needsCapabilities)
        XCTAssertTrue(needs.needsCalendarContext)
        XCTAssertEqual(needs.needsPersonProfiles, ["Alice"])
        XCTAssertTrue(needs.needsLearnings)
        XCTAssertFalse(needs.needsObservations)
        XCTAssertTrue(needs.needsTodayEpisode)
    }

    func testAnalyzeFallsBackToKeywordsWhenClaudeMissing() {
        let router = ContextRouter(claudePath: "/missing/claude", timeout: 0.1, enabled: true)
        let needs = router.analyze([makeMessage(text: "Where did we meet last time? Any observations?")])

        XCTAssertTrue(needs.needsLocationContext)
        XCTAssertTrue(needs.needsDecisions)
        XCTAssertTrue(needs.needsObservations)
    }
}
