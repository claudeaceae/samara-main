import XCTest

final class ContextTriggersTests: SamaraTestCase {

    private func makeBaseDir() -> String {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-context-triggers-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.path
    }

    private func makeEmptyTriggers(baseDir: String) -> ContextTriggers {
        let triggers = ContextTriggers(baseDir: baseDir)
        for trigger in triggers.getAllTriggers() {
            triggers.removeTrigger(id: trigger.id)
        }
        return triggers
    }

    func testEvaluateMatchesTimePatternAndExpandsTemplate() {
        let baseDir = makeBaseDir()
        let triggers = makeEmptyTriggers(baseDir: baseDir)

        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 22
        components.hour = 23
        components.minute = 30
        let date = calendar.date(from: components)!
        let weekday = calendar.component(.weekday, from: date)

        let range = ContextTriggers.Condition.TimeRange(startHour: 22, startMinute: 0, endHour: 2, endMinute: 0)
        let trigger = ContextTriggers.Trigger(
            id: "night-check",
            name: "Night Check",
            conditions: [
                .timeOfDay(range),
                .dayOfWeek([weekday]),
                .patternMatch(pattern: "focus")
            ],
            action: .sendMessage(template: "{city} {weather} at {time}"),
            priority: .high,
            cooldown: 0,
            lastFired: nil,
            fireCount: 0
        )

        triggers.addTrigger(trigger)

        let context = ContextTriggers.Context(
            timestamp: date,
            location: .init(latitude: 47.0, longitude: -122.0, city: "Seattle", region: "WA"),
            weather: .init(condition: .rainy, temperature: 12.4, description: nil),
            calendar: [],
            batteryLevel: 0.6,
            lastMessageTime: date.addingTimeInterval(-600),
            recentContext: "Stay focused on the main project"
        )

        let results = triggers.evaluate(context: context)
        let match = results.first { $0.trigger.id == "night-check" }

        XCTAssertNotNil(match)
        XCTAssertTrue(match?.suggestedAction.contains("Send message") == true)
        XCTAssertTrue(match?.suggestedAction.contains("rainy") == true)
        XCTAssertTrue(match?.suggestedAction.contains("Seattle") == true)
    }

    func testEvaluateMatchesLocationAndCalendar() {
        let baseDir = makeBaseDir()
        let triggers = makeEmptyTriggers(baseDir: baseDir)

        let now = Date()
        let trigger = ContextTriggers.Trigger(
            id: "near-event",
            name: "Near Event",
            conditions: [
                .locationNear(latitude: 47.0, longitude: -122.0, radiusMeters: 200),
                .calendarEventSoon(minutesBefore: 30)
            ],
            action: .queueThought(thought: "Prep for {day} event"),
            priority: .medium,
            cooldown: 0,
            lastFired: nil,
            fireCount: 0
        )

        triggers.addTrigger(trigger)

        let event = ContextTriggers.Context.CalendarEvent(
            title: "Planning",
            startTime: now.addingTimeInterval(20 * 60),
            location: "Office"
        )

        let context = ContextTriggers.Context(
            timestamp: now,
            location: .init(latitude: 47.0, longitude: -122.0, city: "Seattle", region: "WA"),
            weather: nil,
            calendar: [event],
            batteryLevel: nil,
            lastMessageTime: now.addingTimeInterval(-60),
            recentContext: nil
        )

        let results = triggers.evaluate(context: context)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.trigger.id, "near-event")
    }

    func testMarkFiredUpdatesTriggerState() {
        let baseDir = makeBaseDir()
        let triggers = makeEmptyTriggers(baseDir: baseDir)

        let trigger = ContextTriggers.Trigger(
            id: "mark-fired",
            name: "Mark Fired",
            conditions: [
                .noMessagesSince(minutes: 5)
            ],
            action: .checkIn,
            priority: .low,
            cooldown: 10,
            lastFired: nil,
            fireCount: 0
        )

        triggers.addTrigger(trigger)
        triggers.markFired(triggerId: "mark-fired")

        let stored = triggers.getAllTriggers().first { $0.id == "mark-fired" }
        XCTAssertNotNil(stored?.lastFired)
        XCTAssertEqual(stored?.fireCount, 1)
    }
}
