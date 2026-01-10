import Foundation
import SQLite3

/// Errors that can occur during memory database operations
enum MemoryDatabaseError: Error, CustomStringConvertible {
    case databaseNotFound
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case migrationFailed(String)

    var description: String {
        switch self {
        case .databaseNotFound:
            return "Memory database not found"
        case .openFailed(let msg):
            return "Failed to open database: \(msg)"
        case .prepareFailed(let msg):
            return "Failed to prepare statement: \(msg)"
        case .executeFailed(let msg):
            return "Failed to execute query: \(msg)"
        case .migrationFailed(let msg):
            return "Database migration failed: \(msg)"
        }
    }
}

/// Native Swift wrapper for SQLite + FTS5 memory database
/// Provides efficient full-text search over memory files without subprocess overhead
final class MemoryDatabase {

    // MARK: - Types

    /// A memory entry from the database
    struct MemoryEntry {
        let id: Int64
        let content: String
        let context: String?
        let memoryType: String
        let episodeDate: String?
        let sourceFile: String?
        let sourceLine: Int?
        let createdAt: Date
        let rank: Double  // BM25 rank from FTS5
    }

    /// Memory types for categorization
    enum MemoryType: String {
        case episode = "episode"
        case learning = "learning"
        case observation = "observation"
        case decision = "decision"
        case reflection = "reflection"
        case question = "question"
    }

    // MARK: - Properties

    private let dbPath: String
    private var db: OpaquePointer?

    /// Whether the database is currently open
    var isOpen: Bool { db != nil }

    // MARK: - Initialization

    /// Initialize with path to database file
    /// - Parameter dbPath: Path to SQLite database (default: ~/.claude-mind/semantic/memory.db)
    init(dbPath: String? = nil) {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind/semantic/memory.db")
            .path
        self.dbPath = dbPath ?? defaultPath
    }

    deinit {
        close()
    }

    // MARK: - Database Operations

    /// Open the database connection and ensure schema exists
    func open() throws {
        // Ensure directory exists
        let dir = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Open database
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            throw MemoryDatabaseError.openFailed(error)
        }

        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode=WAL;")

        // Create schema if needed
        try createSchema()

        log("Memory database opened: \(dbPath)", level: .info, component: "MemoryDatabase")
    }

    /// Close the database connection
    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
            log("Memory database closed", level: .debug, component: "MemoryDatabase")
        }
    }

    /// Create database schema including FTS5 virtual table
    private func createSchema() throws {
        // Main memories table
        try execute("""
            CREATE TABLE IF NOT EXISTS memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                context TEXT,
                memory_type TEXT NOT NULL,
                episode_date TEXT,
                source_file TEXT,
                source_line INTEGER,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            );
        """)

        // FTS5 virtual table with Porter stemming and Unicode tokenization
        // Using external content table to avoid data duplication
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
                content,
                context,
                content='memories',
                content_rowid='id',
                tokenize='porter unicode61'
            );
        """)

        // Triggers to keep FTS in sync with main table
        try execute("""
            CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
                INSERT INTO memories_fts(rowid, content, context)
                VALUES (new.id, new.content, new.context);
            END;
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
                INSERT INTO memories_fts(memories_fts, rowid, content, context)
                VALUES ('delete', old.id, old.content, old.context);
            END;
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
                INSERT INTO memories_fts(memories_fts, rowid, content, context)
                VALUES ('delete', old.id, old.content, old.context);
                INSERT INTO memories_fts(rowid, content, context)
                VALUES (new.id, new.content, new.context);
            END;
        """)

        // Index for common queries
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type);
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_memories_date ON memories(episode_date);
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source_file);
        """)

        log("Database schema verified", level: .debug, component: "MemoryDatabase")
    }

    // MARK: - Search Operations

    /// Search memories using FTS5 full-text search
    /// - Parameters:
    ///   - query: Search query (supports FTS5 syntax)
    ///   - limit: Maximum number of results
    ///   - memoryTypes: Optional filter by memory types
    /// - Returns: Array of matching memories ranked by BM25
    func search(query: String, limit: Int = 10, memoryTypes: [MemoryType]? = nil) throws -> [MemoryEntry] {
        guard let db = db else {
            throw MemoryDatabaseError.databaseNotFound
        }

        // Clean and prepare query for FTS5
        let ftsQuery = prepareFtsQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        // Build SQL with optional type filter
        var sql = """
            SELECT
                m.id,
                m.content,
                m.context,
                m.memory_type,
                m.episode_date,
                m.source_file,
                m.source_line,
                m.created_at,
                bm25(memories_fts) as rank
            FROM memories_fts
            JOIN memories m ON memories_fts.rowid = m.id
            WHERE memories_fts MATCH ?
        """

        if let types = memoryTypes, !types.isEmpty {
            let typeList = types.map { "'\($0.rawValue)'" }.joined(separator: ",")
            sql += " AND m.memory_type IN (\(typeList))"
        }

        sql += " ORDER BY rank LIMIT ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw MemoryDatabaseError.prepareFailed(error)
        }

        sqlite3_bind_text(stmt, 1, ftsQuery, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [MemoryEntry] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = extractMemoryEntry(from: stmt)
            results.append(entry)
        }

        return results
    }

    /// Prepare a user query for FTS5 syntax
    private func prepareFtsQuery(_ query: String) -> String {
        // Extract meaningful words and join with OR for better recall
        let stopWords = Set(["a", "an", "the", "is", "are", "was", "were", "be", "been",
                             "have", "has", "had", "do", "does", "did", "will", "would",
                             "to", "of", "in", "for", "on", "with", "at", "by", "from",
                             "as", "or", "and", "but", "if", "it", "its", "my", "your",
                             "what", "which", "who", "where", "when", "why", "how",
                             "i", "we", "he", "she", "they", "just", "very", "really"])

        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }

        guard !words.isEmpty else { return "" }

        // Use OR for better recall, limit to 10 terms
        let terms = Array(Set(words)).prefix(10)
        return terms.joined(separator: " OR ")
    }

    /// Extract a MemoryEntry from a prepared statement row
    private func extractMemoryEntry(from stmt: OpaquePointer?) -> MemoryEntry {
        let id = sqlite3_column_int64(stmt, 0)
        let content = String(cString: sqlite3_column_text(stmt, 1))
        let context = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
        let memoryType = String(cString: sqlite3_column_text(stmt, 3))
        let episodeDate = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        let sourceFile = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let sourceLine = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil
        let createdAtStr = String(cString: sqlite3_column_text(stmt, 7))
        let rank = sqlite3_column_double(stmt, 8)

        // Parse created_at timestamp
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.date(from: createdAtStr) ?? Date()

        return MemoryEntry(
            id: id,
            content: content,
            context: context,
            memoryType: memoryType,
            episodeDate: episodeDate,
            sourceFile: sourceFile,
            sourceLine: sourceLine,
            createdAt: createdAt,
            rank: rank
        )
    }

    // MARK: - Insert Operations

    /// Insert a new memory entry
    @discardableResult
    func insert(
        content: String,
        context: String? = nil,
        memoryType: MemoryType,
        episodeDate: String? = nil,
        sourceFile: String? = nil,
        sourceLine: Int? = nil
    ) throws -> Int64 {
        guard let db = db else {
            throw MemoryDatabaseError.databaseNotFound
        }

        let sql = """
            INSERT INTO memories (content, context, memory_type, episode_date, source_file, source_line)
            VALUES (?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw MemoryDatabaseError.prepareFailed(error)
        }

        sqlite3_bind_text(stmt, 1, content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if let ctx = context {
            sqlite3_bind_text(stmt, 2, ctx, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 2)
        }

        sqlite3_bind_text(stmt, 3, memoryType.rawValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if let date = episodeDate {
            sqlite3_bind_text(stmt, 4, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 4)
        }

        if let file = sourceFile {
            sqlite3_bind_text(stmt, 5, file, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        if let line = sourceLine {
            sqlite3_bind_int(stmt, 6, Int32(line))
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let error = String(cString: sqlite3_errmsg(db))
            throw MemoryDatabaseError.executeFailed(error)
        }

        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Rebuild from Markdown Files

    /// Rebuild the entire database from markdown memory files
    /// - Parameter mindPath: Path to ~/.claude-mind directory
    func rebuildFromMarkdown(mindPath: String) throws {
        log("Rebuilding memory database from markdown files...", level: .info, component: "MemoryDatabase")

        // Clear existing data
        try execute("DELETE FROM memories;")

        var totalEntries = 0

        // Index episodes
        let episodesPath = (mindPath as NSString).appendingPathComponent("memory/episodes")
        totalEntries += try indexEpisodes(from: episodesPath)

        // Index learnings
        let learningsPath = (mindPath as NSString).appendingPathComponent("memory/learnings.md")
        totalEntries += try indexMarkdownFile(at: learningsPath, type: .learning)

        // Index observations
        let observationsPath = (mindPath as NSString).appendingPathComponent("memory/observations.md")
        totalEntries += try indexMarkdownFile(at: observationsPath, type: .observation)

        // Index decisions
        let decisionsPath = (mindPath as NSString).appendingPathComponent("memory/decisions.md")
        totalEntries += try indexMarkdownFile(at: decisionsPath, type: .decision)

        // Index questions
        let questionsPath = (mindPath as NSString).appendingPathComponent("memory/questions.md")
        totalEntries += try indexMarkdownFile(at: questionsPath, type: .question)

        // Index reflections
        let reflectionsPath = (mindPath as NSString).appendingPathComponent("memory/reflections")
        totalEntries += try indexReflections(from: reflectionsPath)

        // Rebuild FTS index
        try execute("INSERT INTO memories_fts(memories_fts) VALUES('rebuild');")

        log("Memory database rebuilt: \(totalEntries) entries indexed", level: .info, component: "MemoryDatabase")
    }

    /// Index episode files from a directory
    private func indexEpisodes(from path: String) throws -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }

        let files = try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".md") }

        var count = 0
        for file in files {
            let filePath = (path as NSString).appendingPathComponent(file)
            let dateStr = file.replacingOccurrences(of: ".md", with: "")

            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                // Split into paragraphs for better granularity
                let paragraphs = content.components(separatedBy: "\n\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                for (idx, paragraph) in paragraphs.enumerated() {
                    try insert(
                        content: paragraph.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: "Episode from \(dateStr)",
                        memoryType: .episode,
                        episodeDate: dateStr,
                        sourceFile: filePath,
                        sourceLine: idx + 1
                    )
                    count += 1
                }
            }
        }

        return count
    }

    /// Index a markdown file containing bullet points or paragraphs
    private func indexMarkdownFile(at path: String, type: MemoryType) throws -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }

        var count = 0
        var lineNum = 0

        // Split by lines and index each meaningful line
        for line in content.components(separatedBy: .newlines) {
            lineNum += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and headers
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }

            // Clean up bullet points
            var cleanContent = trimmed
            if cleanContent.hasPrefix("- ") {
                cleanContent = String(cleanContent.dropFirst(2))
            } else if cleanContent.hasPrefix("* ") {
                cleanContent = String(cleanContent.dropFirst(2))
            }

            try insert(
                content: cleanContent,
                memoryType: type,
                sourceFile: path,
                sourceLine: lineNum
            )
            count += 1
        }

        return count
    }

    /// Index reflection files from a directory
    private func indexReflections(from path: String) throws -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }

        let files = try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { $0.hasSuffix(".md") }

        var count = 0
        for file in files {
            let filePath = (path as NSString).appendingPathComponent(file)
            let dateStr = file.replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "-reflection", with: "")

            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                // Index as single entry (reflections are meant to be coherent)
                try insert(
                    content: content,
                    context: "Dream cycle reflection",
                    memoryType: .reflection,
                    episodeDate: dateStr,
                    sourceFile: filePath
                )
                count += 1
            }
        }

        return count
    }

    // MARK: - Statistics

    /// Get database statistics
    func getStats() throws -> (totalMemories: Int, byType: [String: Int], databaseSize: Int64) {
        guard let db = db else {
            throw MemoryDatabaseError.databaseNotFound
        }

        var totalMemories = 0
        var byType: [String: Int] = [:]

        // Count total and by type
        let sql = "SELECT memory_type, COUNT(*) FROM memories GROUP BY memory_type;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let type = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int(stmt, 1))
                byType[type] = count
                totalMemories += count
            }
        }

        // Get database file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0

        return (totalMemories, byType, fileSize)
    }

    // MARK: - Helper Methods

    /// Execute a SQL statement
    private func execute(_ sql: String) throws {
        guard let db = db else {
            throw MemoryDatabaseError.databaseNotFound
        }

        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw MemoryDatabaseError.executeFailed(error)
        }
    }
}
