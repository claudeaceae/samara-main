import XCTest

final class CaptureRequestWatcherTests: SamaraTestCase {

    private final class StubCamera: CameraCapturing {
        enum StubError: Error, LocalizedError {
            case failed

            var errorDescription: String? { "Stub failure" }
        }

        let shouldFail: Bool

        init(shouldFail: Bool = false) {
            self.shouldFail = shouldFail
        }

        func capture(to path: String) async throws -> String {
            if shouldFail {
                throw StubError.failed
            }
            return path
        }
    }

    private func makeStateDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeRequest(to path: URL, outputPath: String) throws {
        let payload: [String: Any] = ["output": outputPath]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: path)
    }

    func testCaptureRequestWritesSuccessResult() throws {
        let stateDir = try makeStateDir()
        let requestPath = stateDir.appendingPathComponent("capture-request.json")
        let resultPath = stateDir.appendingPathComponent("capture-result.json")
        let outputPath = stateDir.appendingPathComponent("out.jpg").path

        let watcher = CaptureRequestWatcher(
            statePath: stateDir.path,
            camera: StubCamera(),
            pollInterval: .milliseconds(50)
        )
        watcher.start()
        defer { watcher.stop() }

        try writeRequest(to: requestPath, outputPath: outputPath)

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && !FileManager.default.fileExists(atPath: resultPath.path) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let data = try Data(contentsOf: resultPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["success"] as? Bool, true)
        XCTAssertEqual(json?["path"] as? String, outputPath)
    }

    func testCaptureRequestWritesFailureResult() throws {
        let stateDir = try makeStateDir()
        let requestPath = stateDir.appendingPathComponent("capture-request.json")
        let resultPath = stateDir.appendingPathComponent("capture-result.json")
        let outputPath = stateDir.appendingPathComponent("out.jpg").path

        let watcher = CaptureRequestWatcher(
            statePath: stateDir.path,
            camera: StubCamera(shouldFail: true),
            pollInterval: .milliseconds(50)
        )
        watcher.start()
        defer { watcher.stop() }

        try writeRequest(to: requestPath, outputPath: outputPath)

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && !FileManager.default.fileExists(atPath: resultPath.path) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let data = try Data(contentsOf: resultPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["success"] as? Bool, false)
        XCTAssertEqual(json?["error"] as? String, "Stub failure")
    }
}
