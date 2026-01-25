import XCTest

final class MemoryContextTests: SamaraTestCase {

    private func ensureMindFile(_ relativePath: String, contents: String) throws {
        let url = TestEnvironment.mindPath.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testBuildContextIncludesIdentityAndGoals() {
        try? ensureMindFile("self/identity.md", contents: "# Identity\n\nTest fixture identity for Samara.\n")
        try? ensureMindFile("self/goals.md", contents: "# Goals\n\n- Validate the test harness in an isolated environment.\n")

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

    func testBuildCoreContextIncludesHotDigestWhenAvailable() throws {
        try ensureMindFile("state/hot-digest.md", contents: "## Hot Digest\n- Recent item\n")

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildCoreContext()

        XCTAssertTrue(context.contains("## Hot Digest"))
        XCTAssertTrue(context.contains("Recent item"))
    }

    func testBuildCoreContextFallsBackToOpenThreadsWhenNoDigest() throws {
        let statePath = TestEnvironment.mindPath.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: true)

        let threadsPath = statePath.appendingPathComponent("threads.json")
        let threadsJson = """
        {
          "threads": [
            { "title": "Keep smart context coherent", "status": "open" }
          ]
        }
        """
        try threadsJson.write(to: threadsPath, atomically: true, encoding: .utf8)

        let cachePath = statePath.appendingPathComponent("hot-digest.md")
        try? FileManager.default.removeItem(at: cachePath)

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildCoreContext()

        XCTAssertTrue(context.contains("### Open Threads"))
        XCTAssertTrue(context.contains("Keep smart context coherent"))
    }

    func testBuildSmartContextLoadsRequestedModules() throws {
        try ensureMindFile("self/identity.md", contents: "# Identity\n\nSmart context tests.\n")
        try ensureMindFile("self/goals.md", contents: "# Goals\n\n- Test smart context modules.\n")
        try ensureMindFile("memory/decisions.md", contents: "Decision: Prefer smart context.\n")
        try ensureMindFile("memory/learnings.md", contents: "Learning: Reduce prompt size.\n")
        try ensureMindFile("memory/observations.md", contents: "Observation: Context was bloated.\n")
        try ensureMindFile("memory/people/alice/profile.md", contents: "Alice profile notes.\n")

        var needs = ContextRouter.ContextNeeds()
        needs.needsDecisions = true
        needs.needsLearnings = true
        needs.needsObservations = true
        needs.needsPersonProfiles = ["Alice"]
        needs.needsTodayEpisode = false

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildSmartContext(needs: needs, isCollaboratorChat: true)

        XCTAssertTrue(context.contains("## Architectural Decisions"))
        XCTAssertTrue(context.contains("Decision: Prefer smart context."))
        XCTAssertTrue(context.contains("## Learnings"))
        XCTAssertTrue(context.contains("Learning: Reduce prompt size."))
        XCTAssertTrue(context.contains("## Self-Observations"))
        XCTAssertTrue(context.contains("Observation: Context was bloated."))
        XCTAssertTrue(context.contains("## About Alice"))
    }

    func testBuildSmartContextOmitsCollaboratorProfileForNonCollaboratorChat() throws {
        try ensureMindFile("memory/people/tester/profile.md", contents: "Tester profile notes.\n")

        var needs = ContextRouter.ContextNeeds()
        needs.needsPersonProfiles = ["Tester"]
        needs.needsTodayEpisode = false

        let contextBuilder = MemoryContext()
        let context = contextBuilder.buildSmartContext(needs: needs, isCollaboratorChat: false)

        XCTAssertFalse(context.contains("## About Tester"))
    }
}
