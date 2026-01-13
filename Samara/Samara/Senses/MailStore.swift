import Foundation

/// Represents an email message
struct Email {
    let id: String              // Unique identifier (message id from Mail.app)
    let subject: String
    let sender: String          // Email address
    let senderName: String      // Display name
    let date: Date
    let content: String         // Plain text body
    let isRead: Bool

    /// Returns a description suitable for Claude
    var fullDescription: String {
        var parts: [String] = []
        parts.append("Subject: \(subject)")
        if !content.isEmpty {
            parts.append(content)
        }
        return parts.joined(separator: "\n")
    }
}

/// Reads emails from Apple Mail via AppleScript
final class MailStore {

    typealias AppleScriptRunner = (String) throws -> String

    /// Email addresses to watch for
    private let targetEmails: Set<String>

    /// Account to check (nil = all accounts)
    private let accountName: String?

    private let appleScriptRunner: AppleScriptRunner

    init(
        targetEmails: [String],
        accountName: String? = "iCloud",
        appleScriptRunner: @escaping AppleScriptRunner = MailStore.runAppleScript
    ) {
        self.targetEmails = Set(targetEmails.map { $0.lowercased() })
        self.accountName = accountName
        self.appleScriptRunner = appleScriptRunner
    }

    /// Fetches unread emails from target senders
    func fetchUnreadEmails() throws -> [Email] {
        let script: String
        if let account = accountName {
            script = """
                tell application "Mail"
                    set inboxMsgs to messages of mailbox "INBOX" of account "\(account)"
                    set results to ""
                    repeat with m in inboxMsgs
                        if read status of m is false then
                            set msgId to id of m
                            set msgSubject to subject of m
                            set msgSender to sender of m
                            set msgDate to date received of m
                            set msgContent to content of m
                            -- Use ASCII 30 (record separator) and ASCII 31 (unit separator) as delimiters
                            set results to results & msgId & (ASCII character 31) & msgSubject & (ASCII character 31) & msgSender & (ASCII character 31) & msgDate & (ASCII character 31) & msgContent & (ASCII character 30)
                        end if
                    end repeat
                    return results
                end tell
                """
        } else {
            script = """
                tell application "Mail"
                    set results to ""
                    repeat with acct in accounts
                        try
                            set inboxMsgs to messages of mailbox "INBOX" of acct
                            repeat with m in inboxMsgs
                                if read status of m is false then
                                    set msgId to id of m
                                    set msgSubject to subject of m
                                    set msgSender to sender of m
                                    set msgDate to date received of m
                                    set msgContent to content of m
                                    set results to results & msgId & (ASCII character 31) & msgSubject & (ASCII character 31) & msgSender & (ASCII character 31) & msgDate & (ASCII character 31) & msgContent & (ASCII character 30)
                                end if
                            end repeat
                        end try
                    end repeat
                    return results
                end tell
                """
        }

        let output = try appleScriptRunner(script)
        return parseEmails(output)
    }

    /// Fetches recent emails from target senders (read or unread)
    func fetchRecentEmails(limit: Int = 10) throws -> [Email] {
        let script: String
        if let account = accountName {
            script = """
                tell application "Mail"
                    set inboxMsgs to messages of mailbox "INBOX" of account "\(account)"
                    set results to ""
                    set msgCount to 0
                    repeat with m in inboxMsgs
                        if msgCount >= \(limit) then exit repeat
                        set msgId to id of m
                        set msgSubject to subject of m
                        set msgSender to sender of m
                        set msgDate to date received of m
                        set msgContent to content of m
                        set isRead to read status of m
                        set results to results & msgId & (ASCII character 31) & msgSubject & (ASCII character 31) & msgSender & (ASCII character 31) & msgDate & (ASCII character 31) & msgContent & (ASCII character 31) & isRead & (ASCII character 30)
                        set msgCount to msgCount + 1
                    end repeat
                    return results
                end tell
                """
        } else {
            script = """
                tell application "Mail"
                    set results to ""
                    set msgCount to 0
                    repeat with acct in accounts
                        if msgCount >= \(limit) then exit repeat
                        try
                            set inboxMsgs to messages of mailbox "INBOX" of acct
                            repeat with m in inboxMsgs
                                if msgCount >= \(limit) then exit repeat
                                set msgId to id of m
                                set msgSubject to subject of m
                                set msgSender to sender of m
                                set msgDate to date received of m
                                set msgContent to content of m
                                set isRead to read status of m
                                set results to results & msgId & (ASCII character 31) & msgSubject & (ASCII character 31) & msgSender & (ASCII character 31) & msgDate & (ASCII character 31) & msgContent & (ASCII character 31) & isRead & (ASCII character 30)
                                set msgCount to msgCount + 1
                            end repeat
                        end try
                    end repeat
                    return results
                end tell
                """
        }

        let output = try appleScriptRunner(script)
        return parseEmails(output, includeReadStatus: true)
    }

    /// Mark an email as read
    func markAsRead(emailId: String) throws {
        let script: String
        if let account = accountName {
            script = """
                tell application "Mail"
                    set msgs to messages of mailbox "INBOX" of account "\(account)"
                    repeat with m in msgs
                        if id of m is \(emailId) then
                            set read status of m to true
                            exit repeat
                        end if
                    end repeat
                end tell
                """
        } else {
            script = """
                tell application "Mail"
                    repeat with acct in accounts
                        try
                            set msgs to messages of mailbox "INBOX" of acct
                            repeat with m in msgs
                                if id of m is \(emailId) then
                                    set read status of m to true
                                    return
                                end if
                            end repeat
                        end try
                    end repeat
                end tell
                """
        }

        _ = try appleScriptRunner(script)
    }

    /// Send an email reply
    func sendReply(to email: String, subject: String, body: String) throws {
        // Escape special characters for AppleScript
        let escapedBody = body.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSubject = subject.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Mail"
                set newMsg to make new outgoing message with properties {subject:"\(escapedSubject)", content:"\(escapedBody)", visible:false}
                tell newMsg
                    make new to recipient at end of to recipients with properties {address:"\(email)"}
                end tell
                send newMsg
            end tell
            """

        _ = try appleScriptRunner(script)
    }

    /// Check if an email is from one of the target senders
    func isFromTarget(_ email: Email) -> Bool {
        // Extract email address from sender field (format: "Name <email>" or just "email")
        let senderLower = email.sender.lowercased()
        for target in targetEmails {
            if senderLower.contains(target) {
                return true
            }
        }
        return false
    }

    // MARK: - Private

    /// Timeout for AppleScript execution (30 seconds)
    /// If Mail.app hangs, we don't want to block the thread forever
    private static let appleScriptTimeout: TimeInterval = 30

    private static func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Ensure pipes are closed to prevent file descriptor leaks
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Wait with timeout to prevent blocking forever if Mail.app hangs
        let deadline = Date().addingTimeInterval(appleScriptTimeout)
        while process.isRunning {
            if Date() > deadline {
                log("[MailStore] AppleScript timeout after \(Int(appleScriptTimeout))s - killing process")
                process.terminate()
                // Give it a moment to terminate
                Thread.sleep(forTimeInterval: 0.5)
                if process.isRunning {
                    // Force kill if still running
                    kill(process.processIdentifier, SIGKILL)
                }
                throw MailStoreError.timeout
            }
            // Brief sleep to avoid busy-waiting
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.terminationStatus != 0 {
            let errorData = errorHandle.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MailStoreError.appleScriptFailed(errorString)
        }

        let outputData = outputHandle.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private func parseEmails(_ output: String, includeReadStatus: Bool = false) -> [Email] {
        var emails: [Email] = []

        // Split by record separator (ASCII 30)
        let records = output.components(separatedBy: "\u{1E}")

        for record in records where !record.isEmpty {
            // Split by unit separator (ASCII 31)
            let fields = record.components(separatedBy: "\u{1F}")

            let expectedFields = includeReadStatus ? 6 : 5
            guard fields.count >= expectedFields else { continue }

            let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let sender = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let dateStr = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let content = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)

            let isRead: Bool
            if includeReadStatus && fields.count >= 6 {
                isRead = fields[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } else {
                isRead = false
            }

            // Parse sender name from "Name <email>" format
            let senderName: String
            if let nameEnd = sender.firstIndex(of: "<") {
                senderName = String(sender[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            } else {
                senderName = sender
            }

            // Parse date (AppleScript returns localized date string)
            let date = parseAppleScriptDate(dateStr) ?? Date()

            emails.append(Email(
                id: id,
                subject: subject,
                sender: sender,
                senderName: senderName,
                date: date,
                content: content,
                isRead: isRead
            ))
        }

        return emails
    }

    private func parseAppleScriptDate(_ dateStr: String) -> Date? {
        // AppleScript returns dates like "Friday, December 19, 2025 at 4:52:43 PM"
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.date(from: dateStr)
    }
}

enum MailStoreError: Error {
    case appleScriptFailed(String)
    case timeout
}
