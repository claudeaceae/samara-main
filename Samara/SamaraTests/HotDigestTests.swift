import XCTest

final class HotDigestTests: SamaraTestCase {

    func testBuildHotDigestUsesCache() throws {
        let mindPath = TestEnvironment.mindPath
        let statePath = mindPath.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let cachePath = statePath.appendingPathComponent("hot-digest.md")
        let cached = "## Cached Digest\nTest cached content."
        try cached.write(to: cachePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: cachePath) }

        let contextBuilder = MemoryContext()
        let digest = contextBuilder.buildHotDigest()

        XCTAssertEqual(digest, cached)
    }

    func testBuildHotDigestSkipsStaleCache() throws {
        let mindPath = TestEnvironment.mindPath
        let binPath = mindPath.appendingPathComponent("system/bin")
        let statePath = mindPath.appendingPathComponent("state")

        try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let cachePath = statePath.appendingPathComponent("hot-digest.md")
        try "stale digest".write(to: cachePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: cachePath) }

        let staleDate = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: cachePath.path)

        let scriptPath = binPath.appendingPathComponent("build-hot-digest")
        let script = """
        #!/bin/bash
        echo "fresh digest"
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        defer { try? FileManager.default.removeItem(at: scriptPath) }

        let contextBuilder = MemoryContext()
        let digest = contextBuilder.buildHotDigest()

        XCTAssertEqual(digest, "fresh digest\n")
    }

    func testBuildHotDigestFallsBackToScript() throws {
        let mindPath = TestEnvironment.mindPath
        let binPath = mindPath.appendingPathComponent("system/bin")
        let statePath = mindPath.appendingPathComponent("state")

        try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let cachePath = statePath.appendingPathComponent("hot-digest.md")
        try? FileManager.default.removeItem(at: cachePath)

        let scriptPath = binPath.appendingPathComponent("build-hot-digest")
        let script = """
        #!/bin/bash
        echo "script digest"
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        defer { try? FileManager.default.removeItem(at: scriptPath) }

        let contextBuilder = MemoryContext()
        let digest = contextBuilder.buildHotDigest()

        XCTAssertEqual(digest, "script digest\n")
    }
}
