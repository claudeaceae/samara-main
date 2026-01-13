import XCTest

final class MemoryDatabaseTests: SamaraTestCase {

    private func makeDatabase() throws -> (MemoryDatabase, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-memory-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("memory.db")
        return (MemoryDatabase(dbPath: dbPath.path), tempDir)
    }

    func testOpenInsertSearchAndClose() throws {
        let (db, _) = try makeDatabase()

        XCTAssertFalse(db.isOpen)
        try db.open()
        XCTAssertTrue(db.isOpen)

        let learningId = try db.insert(
            content: "Remember to buy tea at the market",
            context: "shopping",
            memoryType: .learning,
            episodeDate: "2026-01-10",
            sourceFile: "learnings.md",
            sourceLine: 1
        )
        _ = try db.insert(
            content: "Went to the park for a short walk",
            memoryType: .episode,
            episodeDate: "2026-01-10"
        )

        let results = try db.search(query: "buy tea", limit: 5)
        XCTAssertTrue(results.contains { $0.id == learningId })

        let filtered = try db.search(query: "park", limit: 5, memoryTypes: [.episode])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.memoryType, MemoryDatabase.MemoryType.episode.rawValue)

        let stopWordResults = try db.search(query: "the and", limit: 5)
        XCTAssertTrue(stopWordResults.isEmpty)

        db.close()
        XCTAssertFalse(db.isOpen)
    }

    func testRebuildFromMarkdownIndexesContent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-memory-rebuild-\(UUID().uuidString)")
        let mindRoot = tempRoot.appendingPathComponent(".claude-mind")

        try FileManager.default.createDirectory(at: mindRoot, withIntermediateDirectories: true)

        let episodesDir = mindRoot.appendingPathComponent("memory/episodes")
        let reflectionsDir = mindRoot.appendingPathComponent("memory/reflections")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reflectionsDir, withIntermediateDirectories: true)

        let episodePath = episodesDir.appendingPathComponent("2026-01-01.md")
        try "Episode one.\n\nEpisode two.".write(to: episodePath, atomically: true, encoding: .utf8)

        let learningsPath = mindRoot.appendingPathComponent("memory/learnings.md")
        try "# Learnings\n- Learned A\n* Learned B\n".write(to: learningsPath, atomically: true, encoding: .utf8)

        let observationsPath = mindRoot.appendingPathComponent("memory/observations.md")
        try "Observation one".write(to: observationsPath, atomically: true, encoding: .utf8)

        let questionsPath = mindRoot.appendingPathComponent("memory/questions.md")
        try "Question one".write(to: questionsPath, atomically: true, encoding: .utf8)

        let reflectionPath = reflectionsDir.appendingPathComponent("2026-01-02-reflection.md")
        try "Reflection body".write(to: reflectionPath, atomically: true, encoding: .utf8)

        let dbPath = mindRoot.appendingPathComponent("semantic/memory.db")
        let db = MemoryDatabase(dbPath: dbPath.path)
        try db.open()
        try db.rebuildFromMarkdown(mindPath: mindRoot.path)

        let stats = try db.getStats()
        XCTAssertEqual(stats.totalMemories, 7)
        XCTAssertEqual(stats.byType[MemoryDatabase.MemoryType.episode.rawValue], 2)
        XCTAssertEqual(stats.byType[MemoryDatabase.MemoryType.learning.rawValue], 2)
        XCTAssertEqual(stats.byType[MemoryDatabase.MemoryType.observation.rawValue], 1)
        XCTAssertEqual(stats.byType[MemoryDatabase.MemoryType.question.rawValue], 1)
        XCTAssertEqual(stats.byType[MemoryDatabase.MemoryType.reflection.rawValue], 1)

        db.close()
    }
}
