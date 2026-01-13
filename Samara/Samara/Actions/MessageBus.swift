import Foundation

/// Unified message bus for all outbound messages
/// Ensures all outputs are logged to the episode for a coherent conversation stream
///
/// This is the SINGLE point through which ALL outbound messages flow, ensuring:
/// 1. Coordinated output - no independent fire-and-forget sends
/// 2. Episode logging - every outbound message is recorded with source tag
/// 3. Debug visibility - all sends are logged for future leak diagnosis
final class MessageBus {
    private let sender: MessageSender
    private let episodeLogger: EpisodeLogger
    private let collaboratorName: String

    /// Type of outbound message - determines logging format and source tag
    enum MessageType: String {
        case conversationResponse = "iMessage"    // Response to collaborator's message
        case locationTrigger = "Location"         // Proactive message from location change
        case wakeMessage = "Wake"                 // Wake cycle output
        case alert = "Alert"                      // System alerts (permission dialogs, etc.)
        case autonomous = "Autonomous"            // Autonomous/scheduled messages
        case acknowledgment = "Queue"             // "One sec, busy" messages
        case error = "Error"                      // Error notifications
        case webcam = "Webcam"                    // Webcam capture sharing
        case webFetch = "WebFetch"                // Web content sharing
        case senseEvent = "Sense"                 // Satellite sense events
    }

    init(sender: MessageSender, episodeLogger: EpisodeLogger, collaboratorName: String) {
        self.sender = sender
        self.episodeLogger = episodeLogger
        self.collaboratorName = collaboratorName
    }

    // MARK: - Primary Send Methods

    /// Send a text message and log it to the episode
    /// - Parameters:
    ///   - text: The message content
    ///   - type: The type of message (determines source tag in episode)
    ///   - chatIdentifier: Optional chat ID for group chats; nil sends to default target
    ///   - skipEpisodeLog: If true, skip logging to episode (caller will handle via logExchange)
    func send(_ text: String, type: MessageType, chatIdentifier: String? = nil, isGroupChat: Bool = false, skipEpisodeLog: Bool = false) throws {
        log("[\(type.rawValue)] Sending: \(text.prefix(80))...", level: .info, component: "MessageBus")

        do {
            // Send the message
            if let chatId = chatIdentifier {
                try sender.sendToChat(text, chatIdentifier: chatId)
            } else {
                try sender.send(text)
            }

            // Log to episode with source tag (unless caller will handle via logExchange)
            if !skipEpisodeLog {
                episodeLogger.logOutbound(text, source: type.rawValue)
            }

        } catch {
            log("[\(type.rawValue)] Send failed: \(error)", level: .error, component: "MessageBus")
            throw error
        }
    }

    /// Send an attachment and log it to the episode
    func sendAttachment(filePath: String, type: MessageType, chatIdentifier: String? = nil, isGroupChat: Bool = false) throws {
        let fileName = (filePath as NSString).lastPathComponent
        log("[\(type.rawValue)] Sending attachment: \(fileName)", level: .info, component: "MessageBus")

        do {
            if let chatId = chatIdentifier {
                try sender.sendAttachmentToChat(filePath: filePath, chatIdentifier: chatId)
            } else {
                try sender.sendAttachment(filePath: filePath)
            }

            // Log attachment send to episode
            episodeLogger.logOutbound("[Attachment: \(fileName)]", source: type.rawValue)

        } catch {
            log("[\(type.rawValue)] Attachment send failed: \(error)", level: .error, component: "MessageBus")
            throw error
        }
    }

    // MARK: - Convenience Methods for Common Patterns

    /// Log a conversation exchange (incoming + outgoing)
    /// Use this for the main conversation flow where we have both the incoming message and response
    func logConversationExchange(from sender: String, message: String, response: String, source: String = "iMessage") {
        episodeLogger.logExchange(from: sender, message: message, response: response, source: source)
    }

    /// Send a conversation response (most common case)
    func sendConversationResponse(_ text: String, chatIdentifier: String? = nil, isGroupChat: Bool = false) throws {
        try send(text, type: .conversationResponse, chatIdentifier: chatIdentifier, isGroupChat: isGroupChat)
    }

    /// Send a location-triggered notification
    func sendLocationTrigger(_ text: String) throws {
        try send(text, type: .locationTrigger)
    }

    /// Send an alert message
    func sendAlert(_ text: String) throws {
        try send(text, type: .alert)
    }

    /// Send a queue acknowledgment
    func sendQueueAck(_ text: String) throws {
        try send(text, type: .acknowledgment)
    }
}
