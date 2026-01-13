import Foundation
import SQLite3

final class MessageStoreFixture {
    let dbURL: URL
    let collaboratorHandle = "+15555550123"
    let otherHandle = "+15555550999"
    let directChatIdentifier: String
    let groupChatIdentifier = "ABCDEF1234567890ABCDEF1234567890"
    let directChatId: Int64 = 1
    let groupChatId: Int64 = 2
    let directMessageRowId: Int64 = 10
    let groupMessageRowId: Int64 = 11
    let reactionRowId: Int64 = 12
    let attachmentMessageRowId: Int64 = 13
    let outgoingMessageRowId: Int64 = 14
    let groupMessageGuid = "GUID-GROUP-1"
    let directMessageGuid = "GUID-DIRECT-1"
    let reactionGuid = "GUID-REACTION-1"
    let attachmentFilePath = "~/Pictures/test.png"
    let attachmentTransferName = "photo.png"

    let directMessageDate = Date(timeIntervalSinceReferenceDate: 42)
    let groupMessageDate = Date(timeIntervalSinceReferenceDate: 43)
    let reactionDate = Date(timeIntervalSinceReferenceDate: 44)
    let attachmentDate = Date(timeIntervalSinceReferenceDate: 45)
    let outgoingReadDate = Date(timeIntervalSinceReferenceDate: 46)

    private let tempDir: URL
    private var db: OpaquePointer?

    init() throws {
        directChatIdentifier = collaboratorHandle
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-message-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("chat.db")

        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw MessageStoreFixtureError("Failed to open test database")
        }

        try createSchema()
        try seedData()

        sqlite3_close(db)
        db = nil
    }

    func makeStore() throws -> MessageStore {
        let store = MessageStore(targetHandles: [collaboratorHandle], dbPath: dbURL.path)
        try store.open()
        return store
    }

    func cleanup() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func createSchema() throws {
        try exec("""
            CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
            CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT);
            CREATE TABLE message (
                ROWID INTEGER PRIMARY KEY,
                text TEXT,
                date INTEGER,
                is_from_me INTEGER,
                handle_id INTEGER,
                associated_message_type INTEGER,
                associated_message_guid TEXT,
                cache_has_attachments INTEGER,
                guid TEXT,
                is_read INTEGER,
                date_read INTEGER
            );
            CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
            CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
            CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, filename TEXT, mime_type TEXT, transfer_name TEXT, is_sticker INTEGER);
            CREATE TABLE message_attachment_join (attachment_id INTEGER, message_id INTEGER);
            """)
    }

    private func seedData() throws {
        let directTimestamp = appleTimestamp(directMessageDate)
        let groupTimestamp = appleTimestamp(groupMessageDate)
        let reactionTimestamp = appleTimestamp(reactionDate)
        let attachmentTimestamp = appleTimestamp(attachmentDate)
        let outgoingTimestamp = appleTimestamp(outgoingReadDate)

        try exec("""
            INSERT INTO handle (ROWID, id) VALUES
                (1, '\(collaboratorHandle)'),
                (2, '\(otherHandle)');

            INSERT INTO chat (ROWID, chat_identifier, display_name) VALUES
                (\(directChatId), '\(directChatIdentifier)', NULL),
                (\(groupChatId), '\(groupChatIdentifier)', 'Test Group');

            INSERT INTO chat_handle_join (chat_id, handle_id) VALUES
                (\(directChatId), 1),
                (\(groupChatId), 1),
                (\(groupChatId), 2);

            INSERT INTO message (ROWID, text, date, is_from_me, handle_id, associated_message_type, associated_message_guid, cache_has_attachments, guid, is_read, date_read) VALUES
                (\(directMessageRowId), 'Hello from E', \(directTimestamp), 0, 1, 0, NULL, 0, '\(directMessageGuid)', 0, NULL),
                (\(groupMessageRowId), 'Group hello', \(groupTimestamp), 0, 2, 0, NULL, 0, '\(groupMessageGuid)', 0, NULL),
                (\(reactionRowId), NULL, \(reactionTimestamp), 0, 1, 2001, 'p:0/\(groupMessageGuid)', 0, '\(reactionGuid)', 0, NULL),
                (\(attachmentMessageRowId), NULL, \(attachmentTimestamp), 0, 1, 0, NULL, 1, 'GUID-ATTACH-1', 0, NULL),
                (\(outgoingMessageRowId), 'Outbound reply', \(outgoingTimestamp), 1, 1, 0, NULL, 0, 'GUID-OUT-1', 1, \(outgoingTimestamp));

            INSERT INTO chat_message_join (chat_id, message_id) VALUES
                (\(directChatId), \(directMessageRowId)),
                (\(groupChatId), \(groupMessageRowId)),
                (\(groupChatId), \(reactionRowId)),
                (\(directChatId), \(attachmentMessageRowId)),
                (\(directChatId), \(outgoingMessageRowId));

            INSERT INTO attachment (ROWID, filename, mime_type, transfer_name, is_sticker) VALUES
                (1, '\(attachmentFilePath)', 'image/png', '\(attachmentTransferName)', 0);

            INSERT INTO message_attachment_join (attachment_id, message_id) VALUES
                (1, \(attachmentMessageRowId));
            """)
    }

    private func appleTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000.0)
    }

    private func exec(_ sql: String) throws {
        guard let db = db else {
            throw MessageStoreFixtureError("Database not open")
        }

        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw MessageStoreFixtureError(message)
        }
    }
}

struct MessageStoreFixtureError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
