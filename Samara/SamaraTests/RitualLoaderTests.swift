import XCTest

final class RitualLoaderTests: SamaraTestCase {

    private func makeMindPath() -> String {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-rituals-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.path
    }

    func testWakeTypeFromTime() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2025, month: 12, day: 22, hour: 9, minute: 0))!
        let afternoon = calendar.date(from: DateComponents(year: 2025, month: 12, day: 22, hour: 15, minute: 0))!
        let evening = calendar.date(from: DateComponents(year: 2025, month: 12, day: 22, hour: 21, minute: 0))!
        let dream = calendar.date(from: DateComponents(year: 2025, month: 12, day: 22, hour: 4, minute: 0))!

        XCTAssertEqual(RitualLoader.WakeType.fromTime(morning), .morning)
        XCTAssertEqual(RitualLoader.WakeType.fromTime(afternoon), .afternoon)
        XCTAssertEqual(RitualLoader.WakeType.fromTime(evening), .evening)
        XCTAssertEqual(RitualLoader.WakeType.fromTime(dream), .dream)
    }

    func testRitualParsingAndPrompt() {
        let mindPath = makeMindPath()
        let ritualPath = URL(fileURLWithPath: mindPath).appendingPathComponent("self/ritual.md")
        try? FileManager.default.createDirectory(at: ritualPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let contents = """
        # Rituals

        ## Morning
        ### Context Focus
        - Inbox
        - Calendar
        ### Checks to Perform
        - [ ] Review queue
        ### Behavioral Guidelines
        - Be concise
        ### Tone
        Warm and direct
        ### Time Budget
        20 minutes

        ## Evening
        ### Context Focus
        - Reflections
        ### Tone
        Calm
        """

        try? contents.write(to: ritualPath, atomically: true, encoding: .utf8)

        let loader = RitualLoader(mindPath: mindPath)
        let section = loader.getRitual(for: .morning)

        XCTAssertEqual(section?.contextToLoad, ["Inbox", "Calendar"])
        XCTAssertEqual(section?.checks, ["Review queue"])
        XCTAssertEqual(section?.behavior, ["Be concise"])
        XCTAssertEqual(section?.tone, "Warm and direct")
        XCTAssertEqual(section?.maxDuration, "20 minutes")

        let prompt = loader.getContextPrompt(for: .morning)
        XCTAssertTrue(prompt.contains("## Wake Type: Morning"))
        XCTAssertTrue(prompt.contains("- [ ] Review queue"))
        XCTAssertTrue(prompt.contains("Maximum duration: 20 minutes"))

        let wakeTypes = loader.getDefinedWakeTypes().map { $0.rawValue }
        XCTAssertTrue(wakeTypes.contains("Morning"))
        XCTAssertTrue(wakeTypes.contains("Evening"))
    }
}
