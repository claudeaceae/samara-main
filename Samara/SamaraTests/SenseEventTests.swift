import XCTest

final class SenseEventTests: SamaraTestCase {

    func testDecodesTimestampWithFractionalSeconds() throws {
        let json = """
        {
          "sense": "location",
          "timestamp": "2026-01-10T23:52:07.195Z",
          "priority": "background",
          "data": {
            "count": 2,
            "note": "ok"
          }
        }
        """

        let data = Data(json.utf8)
        let event = try JSONDecoder().decode(SenseEvent.self, from: data)

        XCTAssertEqual(event.sense, "location")
        XCTAssertEqual(event.priority, .background)
        XCTAssertEqual(event.getInt("count"), 2)
        XCTAssertEqual(event.getString("note"), "ok")
    }

    func testDecodesTimestampWithoutFractionalSecondsAndDefaultsPriority() throws {
        let json = """
        {
          "sense": "webhook",
          "timestamp": "2026-01-10T23:52:07Z",
          "data": {
            "active": true
          }
        }
        """

        let data = Data(json.utf8)
        let event = try JSONDecoder().decode(SenseEvent.self, from: data)

        XCTAssertEqual(event.priority, .normal)
        XCTAssertEqual(event.getBool("active"), true)
    }

    func testAnyCodableRoundTrip() throws {
        let payload: [String: AnyCodable] = [
            "name": AnyCodable("samara"),
            "count": AnyCodable(3),
            "flags": AnyCodable(["fast", "safe"]),
            "meta": AnyCodable(["nested": "value", "level": 2])
        ]

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["name"]?.value as? String, "samara")
        XCTAssertEqual(decoded["count"]?.value as? Int, 3)
        XCTAssertEqual(decoded["flags"]?.value as? [String], ["fast", "safe"])

        let meta = decoded["meta"]?.value as? [String: Any]
        XCTAssertEqual(meta?["nested"] as? String, "value")
        XCTAssertEqual(meta?["level"] as? Int, 2)
    }

    func testDescriptionIncludesSense() {
        let event = SenseEvent(sense: "test", timestamp: Date(), priority: .normal)
        XCTAssertTrue(event.description.contains("SenseEvent"))
        XCTAssertTrue(event.description.contains("test"))
    }
}
