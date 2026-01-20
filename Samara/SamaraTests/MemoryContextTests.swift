import XCTest

final class MemoryContextTests: SamaraTestCase {

    private func ensureMindFile(_ relativePath: String, contents: String) throws {
        let url = TestEnvironment.mindPath.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testBuildContextIncludesIdentityAndGoals() {
        try? ensureMindFile("identity.md", contents: "# Identity\n\nTest fixture identity for Samara.\n")
        try? ensureMindFile("goals.md", contents: "# Goals\n\n- Validate the test harness in an isolated environment.\n")

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildContext()

        XCTAssertTrue(context.contains("### Identity"))
        XCTAssertTrue(context.contains("Test fixture identity for Samara."))
        XCTAssertTrue(context.contains("### Goals"))
        XCTAssertTrue(context.contains("Validate the test harness"))
    }

    func testReadInstructionFileAppliesSubstitutions() throws {
        let instructionsDir = TestEnvironment.mindPath.appendingPathComponent("instructions")
        try FileManager.default.createDirectory(at: instructionsDir, withIntermediateDirectories: true)

        let fileURL = instructionsDir.appendingPathComponent("test.md")
        try "Hello {{NAME}}".write(to: fileURL, atomically: true, encoding: .utf8)

        let contextBuilder = MemoryContext()
        let result = contextBuilder.readInstructionFile("test.md", substitutions: ["NAME": "Samara"])

        XCTAssertEqual(result, "Hello Samara")
    }

    func testLoadParticipantProfilesMatchesHandle() {
        try? ensureMindFile("memory/people/tester/profile.md", contents: "Email: tester@example.com\n")

        let contextBuilder = MemoryContext()
        let profiles = contextBuilder.loadParticipantProfiles(handles: ["tester@example.com"])

        XCTAssertNotNil(profiles)
        XCTAssertTrue(profiles?.contains("### tester") == true)
    }

    func testBuildContextOmitsAboutSectionWhenNotCollaboratorChat() {
        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildContext(isCollaboratorChat: false)
        XCTAssertFalse(context.contains("### About"))
    }

    func testBuildContextIncludesOpenThreadsWhenNoHotDigest() throws {
        let statePath = TestEnvironment.mindPath.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let threadsPath = statePath.appendingPathComponent("threads.json")
        let threadsJson = """
        {
          "threads": [
            { "title": "Follow up on memory plan", "status": "open" },
            { "title": "Closed item", "status": "closed" }
          ]
        }
        """
        try threadsJson.write(to: threadsPath, atomically: true, encoding: .utf8)

        let cachePath = statePath.appendingPathComponent("hot-digest.md")
        try? FileManager.default.removeItem(at: cachePath)

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildContext()

        XCTAssertTrue(context.contains("### Open Threads"))
        XCTAssertTrue(context.contains("Follow up on memory plan"))
        XCTAssertFalse(context.contains("Closed item"))
    }
}
