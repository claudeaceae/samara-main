import XCTest

final class LocalModelInvokerTests: XCTestCase {

    private final class StubURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeInvoker(handler: @escaping (URLRequest) throws -> (URLResponse, Data)) -> LocalModelInvoker {
        StubURLProtocol.requestHandler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return LocalModelInvoker(
            endpoint: URL(string: "http://localhost:11434"),
            timeout: 1,
            session: session
        )
    }

    func testInvokeReturnsResponseOnSuccess() async throws {
        let invoker = makeInvoker { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {"message":{"role":"assistant","content":"Hello"},"done":true}
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await invoker.invoke(model: "llama3", prompt: "hi")
        XCTAssertEqual(result, "Hello")
    }

    func testInvokeThrowsModelNotFoundOn404() async {
        let invoker = makeInvoker { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await invoker.invoke(model: "missing", prompt: "hi")
            XCTFail("Expected modelNotFound error")
        } catch let error as LocalModelError {
            guard case .modelNotFound(let model) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(model, "missing")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvokeThrowsServiceUnavailableOn500() async {
        let invoker = makeInvoker { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await invoker.invoke(model: "llama3", prompt: "hi")
            XCTFail("Expected serviceUnavailable error")
        } catch let error as LocalModelError {
            guard case .serviceUnavailable = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvokeThrowsDecodingErrorOnInvalidJSON() async {
        let invoker = makeInvoker { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {"done":true}
            """.data(using: .utf8)!
            return (response, data)
        }

        do {
            _ = try await invoker.invoke(model: "llama3", prompt: "hi")
            XCTFail("Expected decodingError")
        } catch let error as LocalModelError {
            guard case .decodingError = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvokeMapsURLErrorToTimeout() async {
        let invoker = makeInvoker { _ in
            throw URLError(.timedOut)
        }

        do {
            _ = try await invoker.invoke(model: "llama3", prompt: "hi")
            XCTFail("Expected timeout error")
        } catch let error as LocalModelError {
            guard case .timeout = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListModelsReturnsNames() async throws {
        let invoker = makeInvoker { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {"models":[{"name":"llama3"},{"name":"mistral"}]}
            """.data(using: .utf8)!
            return (response, data)
        }

        let models = try await invoker.listModels()
        XCTAssertEqual(models, ["llama3", "mistral"])
    }
}
