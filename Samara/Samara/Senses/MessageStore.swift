import Foundation
import SQLite3

/// Represents an attachment (image, video, audio, etc.)
struct Attachment {
    let filePath: String
    let mimeType: String
    let fileName: String
    let isSticker: Bool

    /// Returns a description suitable for Claude to understand
    var description: String {
        let type = mimeType.split(separator: "/").first ?? "file"
        if isSticker {
            return "[Sticker: \(fileName)]"
        }
        return "[\(type.capitalized): \(fileName) at \(filePath)]"
    }
}

/// Reaction types in iMessage
enum ReactionType: Int {
    case loved = 2000      // ❤️
    case liked = 2001      // 👍
    case disliked = 2002   // 👎
    case laughed = 2003    // 😂
    case emphasized = 2004 // ‼️
    case questioned = 2005 // ❓

    // Removal of reactions (adding 1000)
    case removedLove = 3000
    case removedLike = 3001
    case removedDislike = 3002
    case removedLaugh = 3003
    case removedEmphasis = 3004
    case removedQuestion = 3005

    var emoji: String {
        switch self {
        case .loved: return "❤️"
        case .liked: return "👍"
        case .disliked: return "👎"
        case .laughed: return "😂"
        case .emphasized: return "‼️"
        case .questioned: return "❓"
        case .removedLove: return "removed ❤️"
        case .removedLike: return "removed 👍"
        case .removedDislike: return "removed 👎"
        case .removedLaugh: return "removed 😂"
        case .removedEmphasis: return "removed ‼️"
        case .removedQuestion: return "removed ❓"
        }
    }

    var isRemoval: Bool {
        return rawValue >= 3000
    }
}

/// Represents a message from the Messages database
struct Message {
    let rowId: Int64
    let text: String
    let date: Date
    let isFromMe: Bool
    let handleId: String          // The actual sender's handle (phone/email)
    let chatId: Int64             // The chat this message belongs to
    let isGroupChat: Bool         // True if this is a group chat (not 1:1)
    let chatIdentifier: String    // The chat's identifier (for sending responses)
    let attachments: [Attachment]
    let reactionType: ReactionType?
    let reactedToText: String?    // Preview of what was reacted to

    /// Returns true if this is a reaction rather than a regular message
    var isReaction: Bool {
        return reactionType != nil
    }

    /// Returns true if this message has attachments
    var hasAttachments: Bool {
        return !attachments.isEmpty
    }

    /// Returns true if sender is É (one of the target handles)
    func isFromE(targetHandles: Set<String>) -> Bool {
        return targetHandles.contains(handleId)
    }

    /// Builds a description of the message suitable for Claude
    var fullDescription: String {
        var parts: [String] = []

        // Handle reactions
        if let reaction = reactionType {
            var reactionDesc = "É reacted with \(reaction.emoji)"
            if let preview = reactedToText, !preview.isEmpty {
                let truncated = preview.count > 50 ? String(preview.prefix(50)) + "..." : preview
                reactionDesc += " to: \"\(truncated)\""
            }
            return reactionDesc
        }

        // Handle text
        if !text.isEmpty && text != "￼" && !text.allSatisfy({ $0 == "￼" }) {
            // Filter out object replacement characters
            var cleanText = text.replacingOccurrences(of: "￼", with: "").trimmingCharacters(in: .whitespaces)

            // Handle data URIs (base64 embedded content) - these can be huge and crash Claude
            cleanText = sanitizeDataURIs(cleanText)

            if !cleanText.isEmpty {
                parts.append(cleanText)
            }
        }

        // Handle attachments
        for attachment in attachments {
            parts.append(attachment.description)
        }

        return parts.joined(separator: "\n")
    }

    /// Sanitizes data URIs in text to prevent huge base64 blobs from crashing Claude
    private func sanitizeDataURIs(_ text: String) -> String {
        // Pattern matches data:mimetype;base64,<data>
        let dataURIPattern = #"data:([^;]+);base64,[A-Za-z0-9+/=]{100,}"#

        guard let regex = try? NSRegularExpression(pattern: dataURIPattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        if matches.isEmpty {
            return text
        }

        var result = text
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            if let matchRange = Range(match.range, in: result),
               let mimeRange = Range(match.range(at: 1), in: result) {
                let mimeType = String(result[mimeRange])
                let replacement = "[Embedded \(mimeType) content - data URI removed for processing]"
                result.replaceSubrange(matchRange, with: replacement)
            }
        }

        return result
    }

    /// Builds a description with sender context for group chats
    func fullDescriptionWithSender(targetHandles: Set<String>) -> String {
        let base = fullDescription
        if isGroupChat && !isFromE(targetHandles: targetHandles) {
            // In group chat, prefix with sender if not É
            return "[\(handleId)]: \(base)"
        }
        return base
    }
}

/// Reads messages from the macOS Messages database
final class MessageStore {
    private let dbPath: String
    private var db: OpaquePointer?

    /// Identifiers to filter messages from (phone numbers or emails)
    private let targetHandles: Set<String>

    init(targetHandles: [String]) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(homeDir)/Library/Messages/chat.db"
        self.targetHandles = Set(targetHandles)
    }

    /// Opens the database connection
    func open() throws {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw MessageStoreError.openFailed(errorMessage)
        }
    }

    /// Closes the database connection
    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    /// Fetches the latest ROWID to use as a starting point
    func getLatestRowId() throws -> Int64 {
        guard let db = db else {
            throw MessageStoreError.notConnected
        }

        let query = "SELECT MAX(ROWID) FROM message"
        var statement: OpaquePointer?

        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }

        return 0
    }

    /// Fetches new messages from chats where É is a participant since the given ROWID
    /// This includes messages from anyone in group chats that É is part of
    func fetchNewMessages(since rowId: Int64) throws -> [Message] {
        guard let db = db else {
            throw MessageStoreError.notConnected
        }

        // Debug: uncomment to trace query parameters
        // log("[MessageStore] fetchNewMessages called with rowId: \(rowId), targetHandles: \(targetHandles)")

        // Build placeholders for target handles
        let placeholders = targetHandles.map { _ in "?" }.joined(separator: ", ")

        // Query that correctly identifies:
        // 1. The actual sender (from message.handle_id → sender_handle)
        // 2. The chat info (from chat_message_join → chat)
        // 3. Only chats where É is a participant (EXISTS subquery)
        // 4. Group chat detection via participant count (2+ = group)
        let query = """
            SELECT DISTINCT
                m.ROWID,
                m.text,
                m.date,
                m.is_from_me,
                sender_handle.id as sender_handle,
                c.ROWID as chat_id,
                c.chat_identifier,
                CASE WHEN (SELECT COUNT(*) FROM chat_handle_join WHERE chat_id = c.ROWID) > 1 THEN 1 ELSE 0 END as is_group,
                m.associated_message_type,
                m.associated_message_guid,
                m.cache_has_attachments
            FROM message m
            JOIN handle sender_handle ON m.handle_id = sender_handle.ROWID
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.ROWID > ?
              AND m.is_from_me = 0
              AND EXISTS (
                  SELECT 1 FROM chat_handle_join chj
                  JOIN handle h ON chj.handle_id = h.ROWID
                  WHERE chj.chat_id = c.ROWID
                    AND h.id IN (\(placeholders))
              )
            ORDER BY m.ROWID ASC
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        // Bind parameters: first the rowId, then all target handles
        sqlite3_bind_int64(statement, 1, rowId)

        // SQLITE_TRANSIENT tells SQLite to copy the string immediately
        // This is required because Swift strings are temporary
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, handle) in targetHandles.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 2), handle, -1, SQLITE_TRANSIENT)
        }

        var messages: [Message] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let msgRowId = sqlite3_column_int64(statement, 0)

            // Get text - may be NULL for attachments
            let text: String
            if let textPtr = sqlite3_column_text(statement, 1) {
                text = String(cString: textPtr)
            } else {
                text = ""
            }

            // macOS Messages uses Apple's timestamp: nanoseconds since 2001-01-01
            let dateInt = sqlite3_column_int64(statement, 2)
            let date = dateFromAppleTimestamp(dateInt)

            let isFromMe = sqlite3_column_int(statement, 3) != 0

            // Get sender handle (the actual person who sent this message)
            guard let senderPtr = sqlite3_column_text(statement, 4) else {
                continue
            }
            let senderHandle = String(cString: senderPtr)

            // Get chat info
            let chatId = sqlite3_column_int64(statement, 5)

            guard let chatIdentifierPtr = sqlite3_column_text(statement, 6) else {
                continue
            }
            let chatIdentifier = String(cString: chatIdentifierPtr)

            let isGroupChat = sqlite3_column_int(statement, 7) != 0

            // Get reaction info
            let associatedType = sqlite3_column_int(statement, 8)
            let reactionType = ReactionType(rawValue: Int(associatedType))

            var reactedToText: String? = nil
            if reactionType != nil, let guidPtr = sqlite3_column_text(statement, 9) {
                let guid = String(cString: guidPtr)
                reactedToText = try? getMessageTextByGuid(guid)
            }

            // Get attachments if indicated
            let hasAttachments = sqlite3_column_int(statement, 10) != 0
            var attachments: [Attachment] = []
            if hasAttachments {
                attachments = (try? fetchAttachments(forMessageId: msgRowId)) ?? []
            }

            // Skip empty messages (no text, no attachments, not a reaction)
            if text.isEmpty && attachments.isEmpty && reactionType == nil {
                continue
            }

            // Log message creation for debugging routing issues
            // (keep this - helps diagnose isGroupChat bugs)

            messages.append(Message(
                rowId: msgRowId,
                text: text,
                date: date,
                isFromMe: isFromMe,
                handleId: senderHandle,
                chatId: chatId,
                isGroupChat: isGroupChat,
                chatIdentifier: chatIdentifier,
                attachments: attachments,
                reactionType: reactionType,
                reactedToText: reactedToText
            ))
        }

        return messages
    }

    /// Fetches attachments for a specific message
    private func fetchAttachments(forMessageId messageId: Int64) throws -> [Attachment] {
        guard let db = db else {
            throw MessageStoreError.notConnected
        }

        let query = """
            SELECT a.filename, a.mime_type, a.transfer_name, a.is_sticker
            FROM attachment a
            JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
            WHERE maj.message_id = ?
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(statement, 1, messageId)

        var attachments: [Attachment] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let filenamePtr = sqlite3_column_text(statement, 0) else {
                continue
            }
            let filename = String(cString: filenamePtr)

            let mimeType: String
            if let mimePtr = sqlite3_column_text(statement, 1) {
                mimeType = String(cString: mimePtr)
            } else {
                mimeType = "application/octet-stream"
            }

            let transferName: String
            if let namePtr = sqlite3_column_text(statement, 2) {
                transferName = String(cString: namePtr)
            } else {
                transferName = (filename as NSString).lastPathComponent
            }

            let isSticker = sqlite3_column_int(statement, 3) != 0

            // Expand ~ to full path
            let expandedPath = (filename as NSString).expandingTildeInPath

            attachments.append(Attachment(
                filePath: expandedPath,
                mimeType: mimeType,
                fileName: transferName,
                isSticker: isSticker
            ))
        }

        return attachments
    }

    /// Gets the text of a message by its GUID (for reaction context)
    private func getMessageTextByGuid(_ guid: String) throws -> String? {
        guard let db = db else {
            throw MessageStoreError.notConnected
        }

        // The guid in associated_message_guid has format like "p:0/GUID" or "bp:GUID"
        // Extract just the GUID part
        let cleanGuid: String
        if guid.contains("/") {
            cleanGuid = String(guid.split(separator: "/").last ?? "")
        } else if guid.hasPrefix("bp:") {
            cleanGuid = String(guid.dropFirst(3))
        } else {
            cleanGuid = guid
        }

        let query = "SELECT text FROM message WHERE guid = ? LIMIT 1"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_text(statement, 1, cleanGuid, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            if let textPtr = sqlite3_column_text(statement, 0) {
                return String(cString: textPtr)
            }
        }

        return nil
    }

    /// Converts Apple's timestamp format to Date
    private func dateFromAppleTimestamp(_ timestamp: Int64) -> Date {
        // Apple uses nanoseconds since 2001-01-01
        // We need to convert to seconds and add the reference date offset
        let seconds = Double(timestamp) / 1_000_000_000.0
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Read status for a message
    struct ReadStatus {
        let isRead: Bool
        let readTime: Date?
    }

    /// Check if an outgoing message has been read by the recipient
    /// - Parameter rowId: The ROWID of the message to check
    /// - Returns: ReadStatus indicating if/when the message was read, or nil if not found
    func getReadStatus(forRowId rowId: Int64) -> ReadStatus? {
        guard let db = db else {
            return nil
        }

        let query = "SELECT is_read, date_read FROM message WHERE ROWID = ? AND is_from_me = 1"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_int64(statement, 1, rowId)

        if sqlite3_step(statement) == SQLITE_ROW {
            let isRead = sqlite3_column_int(statement, 0) != 0
            let dateReadInt = sqlite3_column_int64(statement, 1)

            let readTime: Date?
            if dateReadInt > 0 {
                readTime = dateFromAppleTimestamp(dateReadInt)
            } else {
                readTime = nil
            }

            return ReadStatus(isRead: isRead, readTime: readTime)
        }

        return nil
    }

    /// Get the ROWID of the most recent outgoing message to target handles
    func getLastOutgoingMessageRowId() -> Int64? {
        guard let db = db else {
            return nil
        }

        // Build the handle filter
        let placeholders = targetHandles.map { _ in "?" }.joined(separator: ", ")
        let query = """
            SELECT m.ROWID
            FROM message m
            JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.is_from_me = 1
              AND h.id IN (\(placeholders))
            ORDER BY m.ROWID DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        // Bind handle parameters
        // SQLITE_TRANSIENT tells SQLite to copy the string immediately
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, handle) in targetHandles.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), handle, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }

        return nil
    }
}

enum MessageStoreError: Error {
    case openFailed(String)
    case notConnected
    case queryFailed(String)
}
