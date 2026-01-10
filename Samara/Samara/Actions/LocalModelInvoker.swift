import Foundation

/// Errors that can occur when invoking local models
enum LocalModelError: Error, CustomStringConvertible {
    case serviceUnavailable
    case timeout
    case invalidResponse
    case modelNotFound(String)
    case networkError(Error)
    case decodingError(Error)

    var description: String {
        switch self {
        case .serviceUnavailable:
            return "Ollama service is not available"
        case .timeout:
            return "Request to local model timed out"
        case .invalidResponse:
            return "Invalid response from local model"
        case .modelNotFound(let model):
            return "Model '\(model)' not found in Ollama"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

/// Invokes local LLM models via Ollama REST API
/// Used as fallback when Claude API is unavailable
final class LocalModelInvoker {

    // MARK: - Types

    private struct OllamaChatRequest: Encodable {
        let model: String
        let messages: [OllamaMessage]
        let stream: Bool

        struct OllamaMessage: Encodable {
            let role: String
            let content: String
        }
    }

    private struct OllamaChatResponse: Decodable {
        let message: ResponseMessage
        let done: Bool

        struct ResponseMessage: Decodable {
            let role: String
            let content: String
        }
    }

    private struct OllamaTagsResponse: Decodable {
        let models: [ModelInfo]

        struct ModelInfo: Decodable {
            let name: String
        }
    }

    // MARK: - Properties

    private let endpoint: URL
    private let timeout: TimeInterval
    private let session: URLSession

    // MARK: - Initialization

    /// Initialize with Ollama endpoint and timeout
    /// - Parameters:
    ///   - endpoint: Ollama API endpoint (default: http://localhost:11434)
    ///   - timeout: Request timeout in seconds (default: 60)
    init(endpoint: URL? = nil, timeout: TimeInterval = 60) {
        self.endpoint = endpoint ?? URL(string: "http://localhost:11434")!
        self.timeout = timeout

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public Methods

    /// Check if Ollama service is running and available
    /// - Returns: true if Ollama is responding, false otherwise
    func isAvailable() async -> Bool {
        let tagsURL = endpoint.appendingPathComponent("api/tags")
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5  // Quick check timeout

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    /// List available models in Ollama
    /// - Returns: Array of model names
    func listModels() async throws -> [String] {
        let tagsURL = endpoint.appendingPathComponent("api/tags")
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalModelError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw LocalModelError.serviceUnavailable
            }

            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return tagsResponse.models.map { $0.name }
        } catch let error as LocalModelError {
            throw error
        } catch let error as DecodingError {
            throw LocalModelError.decodingError(error)
        } catch {
            throw LocalModelError.networkError(error)
        }
    }

    /// Invoke a local model with a prompt
    /// - Parameters:
    ///   - model: Model name (e.g., "llama3.1:8b", "mistral:7b")
    ///   - prompt: The prompt to send
    ///   - systemPrompt: Optional system prompt for context
    /// - Returns: The model's response text
    func invoke(model: String, prompt: String, systemPrompt: String? = nil) async throws -> String {
        let chatURL = endpoint.appendingPathComponent("api/chat")

        // Build messages array
        var messages: [OllamaChatRequest.OllamaMessage] = []

        if let system = systemPrompt {
            messages.append(OllamaChatRequest.OllamaMessage(role: "system", content: system))
        }

        messages.append(OllamaChatRequest.OllamaMessage(role: "user", content: prompt))

        let chatRequest = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: false
        )

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(chatRequest)

        log("Invoking local model: \(model)", level: .info, component: "LocalModelInvoker")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalModelError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
                let content = chatResponse.message.content
                log("Local model response received (\(content.count) chars)", level: .info, component: "LocalModelInvoker")
                return content

            case 404:
                throw LocalModelError.modelNotFound(model)

            default:
                log("Ollama returned status \(httpResponse.statusCode)", level: .warn, component: "LocalModelInvoker")
                throw LocalModelError.serviceUnavailable
            }
        } catch let error as LocalModelError {
            throw error
        } catch is URLError {
            throw LocalModelError.timeout
        } catch let error as DecodingError {
            throw LocalModelError.decodingError(error)
        } catch {
            throw LocalModelError.networkError(error)
        }
    }

    /// Invoke with simple acknowledgment prompt (for quick responses)
    /// - Parameters:
    ///   - model: Model name
    ///   - context: Brief context about what to acknowledge
    /// - Returns: A simple acknowledgment response
    func invokeSimpleAck(model: String, context: String) async throws -> String {
        let systemPrompt = """
            You are a helpful assistant. Give very brief, friendly acknowledgments.
            Keep responses under 50 words. Be warm but concise.
            """

        let prompt = "Acknowledge this briefly: \(context)"

        return try await invoke(model: model, prompt: prompt, systemPrompt: systemPrompt)
    }

    /// Invoke for status query (e.g., "What time is it?", "Where am I?")
    /// - Parameters:
    ///   - model: Model name
    ///   - query: The status query
    ///   - contextData: Relevant data to answer the query (e.g., current time, location)
    /// - Returns: Response based on the context data
    func invokeStatusQuery(model: String, query: String, contextData: String) async throws -> String {
        let systemPrompt = """
            You are a helpful assistant answering simple status queries.
            Use the provided context data to answer accurately.
            Keep responses brief and direct (under 100 words).
            """

        let prompt = """
            Query: \(query)

            Context data:
            \(contextData)

            Answer the query using the context data provided.
            """

        return try await invoke(model: model, prompt: prompt, systemPrompt: systemPrompt)
    }
}
