import XCTest

final class LocationFileWatcherTests: SamaraTestCase {

    func testCurrentLocationParsesValues() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-location-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let locationPath = tempDir.appendingPathComponent("location.json")
        let json = """
        {
          "lat": 40.7128,
          "lon": -74.0060,
          "altitude": 12.5,
          "speed": 2.4,
          "battery": 0.91,
          "wifi": "TestWiFi",
          "motion": ["walking"],
          "timestamp": "2026-01-10T23:52:07Z"
        }
        """
        try json.write(to: locationPath, atomically: true, encoding: .utf8)

        let watcher = LocationFileWatcher(locationFilePath: locationPath.path, onLocationChanged: { _ in })
        guard let update = watcher.currentLocation() else {
            XCTFail("Expected location update")
            return
        }

        XCTAssertEqual(update.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(update.longitude, -74.0060, accuracy: 0.0001)
        XCTAssertNotNil(update.altitude)
        XCTAssertEqual(update.altitude ?? 0, 12.5, accuracy: 0.0001)
        XCTAssertNotNil(update.speed)
        XCTAssertEqual(update.speed ?? 0, 2.4, accuracy: 0.0001)
        XCTAssertNotNil(update.battery)
        XCTAssertEqual(update.battery ?? 0, 0.91, accuracy: 0.0001)
        XCTAssertEqual(update.wifi, "TestWiFi")
        XCTAssertEqual(update.motion, ["walking"])

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expectedDate = formatter.date(from: "2026-01-10T23:52:07Z")
        XCTAssertEqual(update.timestamp.timeIntervalSince1970, expectedDate?.timeIntervalSince1970 ?? 0, accuracy: 0.5)
    }

    func testCurrentLocationReturnsNilWhenMissing() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-location-missing-\(UUID().uuidString)")
        let locationPath = tempDir.appendingPathComponent("location.json")

        let watcher = LocationFileWatcher(locationFilePath: locationPath.path, onLocationChanged: { _ in })
        XCTAssertNil(watcher.currentLocation())
    }
}
