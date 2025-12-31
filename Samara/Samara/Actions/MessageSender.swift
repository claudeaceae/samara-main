import Foundation

/// Sends messages via Apple Messages using AppleScript
final class MessageSender {
    /// The target phone number or email to send to
    private let targetId: String

    init(targetId: String) {
        self.targetId = targetId
    }

    // MARK: - Public API (1:1 chats via targetId)

    /// Sends a text message to the target (1:1 chat)
    func send(_ text: String) throws {
        // Split long messages to avoid AppleEvent timeout
        let chunks = splitMessage(text, maxLength: 3000)

        for (index, chunk) in chunks.enumerated() {
            let escapedText = escapeForAppleScript(chunk)

            let script = """
                with timeout of 300 seconds
                    tell application "Messages"
                        set targetService to 1st account whose service type = iMessage
                        set targetBuddy to participant "\(targetId)" of targetService
                        send "\(escapedText)" to targetBuddy
                    end tell
                end timeout
                """

            try runAppleScript(script)

            // Small delay between chunks to avoid overwhelming Messages
            if index < chunks.count - 1 {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        print("[MessageSender] Sent message to \(targetId) (\(chunks.count) chunk(s))")
    }

    /// Sends a file/image attachment to the target (1:1 chat)
    /// Uses Pictures folder workaround for macOS Sequoia/Tahoe compatibility
    func sendAttachment(filePath: String) throws {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw MessageSenderError.fileNotFound(filePath)
        }

        // Copy to Pictures folder (required for AppleScript file sending on Sequoia)
        let tempPath = try copyToPicturesFolder(filePath: filePath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let chatId = buildChatId(targetId)
        let script = """
            with timeout of 300 seconds
                tell application "Messages"
                    set targetChat to chat id "\(chatId)"
                    send POSIX file "\(tempPath)" to targetChat
                end tell
            end timeout
            """

        try runAppleScript(script)
        print("[MessageSender] Sent attachment to \(targetId): \(filePath)")
    }

    // MARK: - Public API (specific chat by identifier)

    /// Sends a text message to a specific chat by its identifier
    /// This works for both 1:1 and group chats
    func sendToChat(_ text: String, chatIdentifier: String) throws {
        let chatId = buildChatId(chatIdentifier)

        // Split long messages to avoid AppleEvent timeout
        let chunks = splitMessage(text, maxLength: 3000)

        for (index, chunk) in chunks.enumerated() {
            let escapedText = escapeForAppleScript(chunk)

            let script = """
                with timeout of 300 seconds
                    tell application "Messages"
                        set targetChat to chat id "\(chatId)"
                        send "\(escapedText)" to targetChat
                    end tell
                end timeout
                """

            try runAppleScript(script)

            // Small delay between chunks to avoid overwhelming Messages
            if index < chunks.count - 1 {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        print("[MessageSender] Sent message to chat \(chatIdentifier) (\(chunks.count) chunk(s))")
    }

    /// Sends a file/image attachment to a specific chat
    /// Uses Pictures folder workaround for macOS Sequoia/Tahoe compatibility
    /// Works for both 1:1 and group chats
    func sendAttachmentToChat(filePath: String, chatIdentifier: String) throws {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw MessageSenderError.fileNotFound(filePath)
        }

        // Copy to Pictures folder (required for AppleScript file sending on Sequoia)
        let tempPath = try copyToPicturesFolder(filePath: filePath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let chatId = buildChatId(chatIdentifier)

        let script = """
            with timeout of 300 seconds
                tell application "Messages"
                    set targetChat to chat id "\(chatId)"
                    send POSIX file "\(tempPath)" to targetChat
                end tell
            end timeout
            """

        try runAppleScript(script)
        print("[MessageSender] Sent attachment to chat \(chatIdentifier): \(filePath)")
    }

    // MARK: - Private Helpers

    /// Copies a file to ~/Pictures/.imessage-send/ for sending
    /// Required workaround: AppleScript file sending only works from ~/Pictures on macOS Sequoia/Tahoe
    private func copyToPicturesFolder(filePath: String) throws -> String {
        let fileManager = FileManager.default
        let picturesURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/.imessage-send")

        // Create directory if needed
        try fileManager.createDirectory(at: picturesURL, withIntermediateDirectories: true)

        // Generate unique filename
        let originalName = (filePath as NSString).lastPathComponent
        let uniqueName = "\(Int(Date().timeIntervalSince1970))-\(ProcessInfo.processInfo.processIdentifier)-\(originalName)"
        let destPath = picturesURL.appendingPathComponent(uniqueName).path

        // Copy file
        try fileManager.copyItem(atPath: filePath, toPath: destPath)

        return destPath
    }

    /// Builds the AppleScript chat ID from an identifier
    private func buildChatId(_ chatIdentifier: String) -> String {
        // Chat IDs in AppleScript use different separators:
        // - 1:1 chats (phone/email): "any;-;{identifier}"
        // - Group chats (GUID): "any;+;{identifier}"
        let separator = isGroupChatIdentifier(chatIdentifier) ? "+" : "-"
        return "any;\(separator);\(chatIdentifier)"
    }

    /// Determines if a chat identifier is for a group chat (GUID) vs 1:1 (phone/email)
    private func isGroupChatIdentifier(_ identifier: String) -> Bool {
        // Group chat identifiers are hex GUIDs (32 chars of alphanumerics)
        // 1:1 identifiers start with + (phone) or contain @ (email)
        if identifier.hasPrefix("+") || identifier.contains("@") {
            return false
        }
        // Check if it looks like a hex GUID (32 alphanumeric chars)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return identifier.count == 32 && identifier.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }

    /// Escapes text for inclusion in AppleScript strings
    private func escapeForAppleScript(_ text: String) -> String {
        var escaped = text
        // Escape backslashes first
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        // Escape double quotes
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    /// Splits a message into chunks at paragraph boundaries
    private func splitMessage(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""

        // Split by double newlines (paragraphs) first
        let paragraphs = text.components(separatedBy: "\n\n")

        for paragraph in paragraphs {
            let paragraphWithBreak = paragraph + "\n\n"

            if currentChunk.count + paragraphWithBreak.count <= maxLength {
                currentChunk += paragraphWithBreak
            } else {
                // Save current chunk if not empty
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                // If single paragraph is too long, split by sentences
                if paragraph.count > maxLength {
                    let sentences = paragraph.components(separatedBy: ". ")
                    currentChunk = ""
                    for sentence in sentences {
                        let sentenceWithPeriod = sentence + ". "
                        if currentChunk.count + sentenceWithPeriod.count <= maxLength {
                            currentChunk += sentenceWithPeriod
                        } else {
                            if !currentChunk.isEmpty {
                                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            currentChunk = sentenceWithPeriod
                        }
                    }
                } else {
                    currentChunk = paragraphWithBreak
                }
            }
        }

        // Add remaining content
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks.isEmpty ? [text] : chunks
    }

    /// Runs an AppleScript via osascript command
    private func runAppleScript(_ source: String) throws {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MessageSenderError.executionFailed(error.localizedDescription)
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MessageSenderError.executionFailed(errorMessage)
        }
    }
}

enum MessageSenderError: Error {
    case scriptCreationFailed
    case executionFailed(String)
    case fileNotFound(String)
}
