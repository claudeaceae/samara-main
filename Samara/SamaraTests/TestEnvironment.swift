import Foundation

enum TestEnvironment {
    private static let lock = NSLock()
    private static var installed = false

    static let mindPath: URL = {
        let env = ProcessInfo.processInfo.environment
        if let rawPath = env["SAMARA_MIND_PATH"] ?? env["MIND_PATH"] {
            let expanded = (rawPath as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-tests-\(UUID().uuidString)")
        return tempRoot.appendingPathComponent(".claude-mind")
    }()

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard !installed else { return }
        installed = true

        let path = mindPath.path
        setenv("SAMARA_MIND_PATH", path, 1)
        setenv("MIND_PATH", path, 1)
        setenv("SAMARA_TEST_MODE", "1", 1)

        let fm = FileManager.default

        if !fm.fileExists(atPath: mindPath.path) {
            if let fixtureURL = fixtureURL(), fm.fileExists(atPath: fixtureURL.path) {
                do {
                    try fm.copyItem(at: fixtureURL, to: mindPath)
                    return
                } catch {
                    report("failed to copy fixture: \(error)")
                }
            }

            do {
                try fm.createDirectory(at: mindPath, withIntermediateDirectories: true)
            } catch {
                report("failed to create mind path: \(error)")
            }
        }

        ensureConfigIfNeeded()
        ensureEpisodesDirectory()
    }

    private static func ensureConfigIfNeeded() {
        let configURL = mindPath.appendingPathComponent("system/config.json")
        let fm = FileManager.default

        guard !fm.fileExists(atPath: configURL.path) else { return }

        let configDir = configURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: configDir.path) {
            try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        if let fixtureConfig = fixtureURL()?.appendingPathComponent("system/config.json"),
           fm.fileExists(atPath: fixtureConfig.path) {
            do {
                try fm.copyItem(at: fixtureConfig, to: configURL)
                return
            } catch {
                report("failed to copy config: \(error)")
            }
        }

        let contents = """
        {
          "entity": {
            "name": "TestClaude",
            "icloud": "test-claude@icloud.com",
            "bluesky": "@test-claude.bsky.social",
            "github": "test-claude"
          },
          "collaborator": {
            "name": "Tester",
            "phone": "+15555550123",
            "email": "tester@example.com",
            "bluesky": "@tester.bsky.social"
          },
          "notes": {
            "location": "Test Location Log",
            "scratchpad": "Test Scratchpad"
          },
          "mail": {
            "account": "iCloud"
          }
        }
        """

        do {
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            report("failed to write config: \(error)")
        }
    }

    private static func ensureEpisodesDirectory() {
        let episodesURL = mindPath.appendingPathComponent("memory/episodes")
        do {
            try FileManager.default.createDirectory(at: episodesURL, withIntermediateDirectories: true)
        } catch {
            report("failed to create episodes dir: \(error)")
        }
    }

    private static func fixtureURL() -> URL? {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repoRoot.appendingPathComponent("tests/fixtures/claude-mind")
        return FileManager.default.fileExists(atPath: fixture.path) ? fixture : nil
    }

    private static func report(_ message: String) {
        guard let data = "TestEnvironment: \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
