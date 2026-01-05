import Foundation

/// Routes complex message batches to isolated task handlers
/// This prevents cross-contamination of streams when handling multiple concurrent requests
/// (e.g., webcam capture + web fetch + conversation in the same batch)
final class TaskRouter {

    // MARK: - Types

    struct TaskClassification {
        let type: TaskType
        let messages: [Message]
        let originalIndex: Int  // Preserve ordering for response assembly
    }

    enum TaskType: String {
        case conversation = "conversation"      // Normal chat responses
        case webcamCapture = "webcam"           // "show webcam", "take photo", "camera"
        case webFetch = "web"                   // URLs, "check this out", "look at this"
        case skillInvocation = "skill"          // /commands
        case systemQuery = "system"             // Internal system queries
    }

    // MARK: - Classification

    /// Classify a batch of messages into task types
    /// Messages of the same type are grouped; different types get isolated handling
    func classifyBatch(_ messages: [Message]) -> [TaskClassification] {
        var tasks: [TaskClassification] = []
        var conversational: [(message: Message, index: Int)] = []

        for (index, message) in messages.enumerated() {
            let text = message.text.lowercased()

            // Check for webcam/camera requests
            if isWebcamRequest(text) {
                tasks.append(TaskClassification(
                    type: .webcamCapture,
                    messages: [message],
                    originalIndex: index
                ))
                continue
            }

            // Check for web fetch requests (URLs)
            if isWebFetchRequest(text) {
                tasks.append(TaskClassification(
                    type: .webFetch,
                    messages: [message],
                    originalIndex: index
                ))
                continue
            }

            // Check for skill invocations (slash commands)
            if isSkillInvocation(text) {
                tasks.append(TaskClassification(
                    type: .skillInvocation,
                    messages: [message],
                    originalIndex: index
                ))
                continue
            }

            // Default: conversational message
            conversational.append((message, index))
        }

        // Group conversational messages together (they share session context)
        if !conversational.isEmpty {
            tasks.append(TaskClassification(
                type: .conversation,
                messages: conversational.map { $0.message },
                originalIndex: conversational.first?.index ?? 0
            ))
        }

        // Sort by original index to preserve response ordering
        return tasks.sorted { $0.originalIndex < $1.originalIndex }
    }

    /// Check if the batch should be split into isolated tasks
    /// Returns true if there are multiple task types that need isolation
    func shouldIsolateTasks(_ messages: [Message]) -> Bool {
        let classifications = classifyBatch(messages)

        // If there's only one task (even if multiple messages), no isolation needed
        if classifications.count <= 1 {
            return false
        }

        // If there are multiple task types, isolation is recommended
        let taskTypes = Set(classifications.map { $0.type })
        return taskTypes.count > 1
    }

    // MARK: - Task Detection Helpers

    private func isWebcamRequest(_ text: String) -> Bool {
        let webcamKeywords = [
            "webcam", "camera", "take photo", "take a photo", "take picture",
            "show me what you see", "capture", "snap", "selfie", "look around"
        ]
        return webcamKeywords.contains { text.contains($0) }
    }

    private func isWebFetchRequest(_ text: String) -> Bool {
        // Check for URLs
        if text.contains("http://") || text.contains("https://") {
            return true
        }

        // Check for web-related keywords
        let webKeywords = [
            "check this out", "look at this", "check this link",
            "what's at", "fetch this", "read this url"
        ]
        return webKeywords.contains { text.contains($0) }
    }

    private func isSkillInvocation(_ text: String) -> Bool {
        // Skill invocations start with /
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("/")
    }

    // MARK: - Isolated Execution

    /// Execute tasks with isolation where needed
    /// Returns array of (TaskType, response) tuples in original order
    func executeWithIsolation(
        tasks: [TaskClassification],
        invoker: ClaudeInvoker,
        context: String,
        sessionId: String?,
        targetHandles: Set<String>
    ) async throws -> [(TaskType, String)] {

        // If only conversation tasks, use normal session-based invocation
        if tasks.count == 1 && tasks[0].type == .conversation {
            let result = try invoker.invokeBatch(
                messages: tasks[0].messages,
                context: context,
                resumeSessionId: sessionId,
                targetHandles: targetHandles
            )
            return [(.conversation, result.response)]
        }

        // Multiple task types - execute in parallel with isolation
        return try await withThrowingTaskGroup(of: (Int, TaskType, String).self) { group in
            for task in tasks {
                group.addTask {
                    let response: String

                    switch task.type {
                    case .conversation:
                        // Conversation tasks get the session context
                        let result = try invoker.invokeBatch(
                            messages: task.messages,
                            context: context,
                            resumeSessionId: sessionId,
                            targetHandles: targetHandles
                        )
                        response = result.response

                    case .webcamCapture, .webFetch, .skillInvocation, .systemQuery:
                        // Other tasks get isolated invocation (no session)
                        let result = try invoker.invokeBatch(
                            messages: task.messages,
                            context: context,
                            resumeSessionId: nil,  // No session = isolated
                            targetHandles: targetHandles
                        )
                        response = result.response
                    }

                    return (task.originalIndex, task.type, response)
                }
            }

            // Collect results and sort by original index
            var results: [(Int, TaskType, String)] = []
            for try await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map { ($0.1, $0.2) }
        }
    }

    // MARK: - Response Assembly

    /// Combine multiple task responses into a single coherent response
    /// Used when sending back to the user after parallel execution
    func assembleResponses(_ results: [(TaskType, String)]) -> String {
        // If single result, return as-is
        if results.count == 1 {
            return results[0].1
        }

        // Multiple results - combine with separators
        // Don't add prefixes for simple cases, just join with double newlines
        return results.map { $0.1 }.joined(separator: "\n\n")
    }
}
