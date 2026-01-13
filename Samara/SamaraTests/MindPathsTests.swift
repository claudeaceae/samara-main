import XCTest

final class MindPathsTests: SamaraTestCase {

    private func withEnvironment(samara: String?, mind: String?, _ block: () throws -> Void) rethrows {
        let originalSamara = getenv("SAMARA_MIND_PATH")
        let originalMind = getenv("MIND_PATH")

        if let samara {
            setenv("SAMARA_MIND_PATH", samara, 1)
        } else {
            unsetenv("SAMARA_MIND_PATH")
        }

        if let mind {
            setenv("MIND_PATH", mind, 1)
        } else {
            unsetenv("MIND_PATH")
        }

        defer {
            if let originalSamara {
                setenv("SAMARA_MIND_PATH", originalSamara, 1)
            } else {
                unsetenv("SAMARA_MIND_PATH")
            }
            if let originalMind {
                setenv("MIND_PATH", originalMind, 1)
            } else {
                unsetenv("MIND_PATH")
            }
        }

        try block()
    }

    func testMindPathsPrefersSamaraOverride() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-mindpaths-samara")
        let samaraPath = tempRoot.appendingPathComponent(".claude-mind").path
        let mindPath = tempRoot.appendingPathComponent("alt-mind").path

        try withEnvironment(samara: samaraPath, mind: mindPath) {
            XCTAssertEqual(MindPaths.mindPath(), samaraPath)
        }
    }

    func testMindPathsUsesMindPathWhenSamaraMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-mindpaths-mind")
        let mindPath = tempRoot.appendingPathComponent(".claude-mind").path

        try withEnvironment(samara: nil, mind: mindPath) {
            XCTAssertEqual(MindPaths.mindPath(), mindPath)
        }
    }

    func testConfigurationLoadUsesMindPath() {
        let config = Configuration.load()
        XCTAssertEqual(config.entity.name, "TestClaude")
        XCTAssertEqual(config.collaborator.name, "Tester")
        XCTAssertEqual(config.collaborator.phone, "+15555550123")
    }

    func testEpisodeLoggerWritesToMindPath() {
        let logger = EpisodeLogger()
        logger.logNote("Test note", source: "Test")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let episodePath = TestEnvironment.mindPath
            .appendingPathComponent("memory/episodes/\(today).md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: episodePath.path))
    }
}
