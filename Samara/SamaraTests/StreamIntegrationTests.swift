import XCTest

final class StreamIntegrationTests: SamaraTestCase {

    private func waitForFileContains(_ url: URL, substring: String, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: url, encoding: .utf8),
               contents.contains(substring) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    private func makeStreamRecorder() throws -> URL {
        let mindPath = TestEnvironment.mindPath
        let binPath = mindPath.appendingPathComponent("system/bin")
        let statePath = mindPath.appendingPathComponent("state")

        try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let logPath = statePath.appendingPathComponent("stream-invocations-\(UUID().uuidString).log")
        let scriptPath = binPath.appendingPathComponent("stream")

        let script = """
        #!/bin/bash
        echo "$@" >> "\(logPath.path)"
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        return logPath
    }

    func testEpisodeLoggerInvokesStreamScript() throws {
        let logPath = try makeStreamRecorder()

        let logger = EpisodeLogger()
        logger.logExchange(from: "E", message: "Hello", response: "Hi", source: "iMessage")

        XCTAssertTrue(waitForFileContains(logPath, substring: "--surface imessage"))
        XCTAssertTrue(waitForFileContains(logPath, substring: "--direction inbound"))
    }

    func testEpisodeLoggerMapsSourcesToSurfaces() throws {
        let logPath = try makeStreamRecorder()
        let logger = EpisodeLogger()

        let cases: [(source: String, expectedSurface: String)] = [
            ("Email", "email"),
            ("Sense:bluesky", "bluesky"),
            ("Sense:x", "x"),
            ("Sense:meeting_prep", "calendar"),
        ]

        for (source, expectedSurface) in cases {
            logger.logExchange(from: source, message: "Ping", response: "Pong", source: source)
            XCTAssertTrue(waitForFileContains(logPath, substring: "--surface \(expectedSurface)"))
        }

        logger.logSenseEvent(sense: "location", data: "Lat: 1, Lon: 2")
        XCTAssertTrue(waitForFileContains(logPath, substring: "--surface location"))
    }
}
