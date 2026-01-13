import XCTest

final class SenseDirectoryWatcherTests: SamaraTestCase {

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-senses-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeEvent(to url: URL, sense: String = "test") throws {
        let json = """
        {
          "sense": "\(sense)",
          "timestamp": "2026-01-10T23:52:07Z",
          "priority": "normal",
          "data": { "msg": "hi" }
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    func testIgnoresExistingEventFilesOnStart() throws {
        let dir = try makeTempDir()
        let existingFile = dir.appendingPathComponent("existing.event.json")
        try writeEvent(to: existingFile)

        let expectation = expectation(description: "no callback")
        expectation.isInverted = true

        let watcher = SenseDirectoryWatcher(
            sensesDirectory: dir.path,
            pollInterval: 0.1,
            onSenseEvent: { _ in expectation.fulfill() }
        )

        watcher.start()
        defer { watcher.stop() }

        wait(for: [expectation], timeout: 0.3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile.path))
    }

    func testProcessesNewEventAndDeletesFile() throws {
        let dir = try makeTempDir()
        let eventFile = dir.appendingPathComponent("new.event.json")

        let expectation = expectation(description: "callback")
        var receivedSense: String?

        let watcher = SenseDirectoryWatcher(
            sensesDirectory: dir.path,
            pollInterval: 0.1,
            onSenseEvent: { event in
                receivedSense = event.sense
                expectation.fulfill()
            }
        )

        watcher.start()
        defer { watcher.stop() }

        try writeEvent(to: eventFile, sense: "location")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedSense, "location")
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventFile.path))
    }

    func testMovesInvalidEventToFailed() throws {
        let dir = try makeTempDir()
        let badFile = dir.appendingPathComponent("bad.event.json")

        let watcher = SenseDirectoryWatcher(
            sensesDirectory: dir.path,
            pollInterval: 0.1,
            onSenseEvent: { _ in }
        )

        watcher.start()
        defer { watcher.stop() }

        try "not json".write(to: badFile, atomically: true, encoding: .utf8)

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let failedPath = dir.appendingPathComponent("bad.failed.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedPath.path))
    }
}
