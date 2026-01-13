import XCTest

final class ModelFallbackChainTests: SamaraTestCase {

    private struct DummyError: Error, CustomStringConvertible {
        let description: String
    }

    private func makeChain() -> ModelFallbackChain {
        let config = Configuration.ModelsConfig(
            primary: "claude",
            fallbacks: ["ollama:llama3.1:8b"],
            localEndpoint: "http://localhost:11434",
            taskClassification: nil
        )
        let invoker = LocalModelInvoker(endpoint: URL(string: "http://localhost:11434")!, timeout: 0.1)
        return ModelFallbackChain(config: config, localInvoker: invoker, timeoutConfig: .defaults)
    }

    func testClassifyTaskAcknowledgment() {
        let chain = makeChain()
        XCTAssertEqual(chain.classifyTask("ok"), .simpleAck)
    }

    func testClassifyTaskStatusQuery() {
        let chain = makeChain()
        XCTAssertEqual(chain.classifyTask("What time is it?"), .statusQuery)
    }

    func testClassifyTaskComplex() {
        let chain = makeChain()
        XCTAssertEqual(chain.classifyTask("Please design a system"), .complex)
    }

    func testStartingTierForComplexity() {
        let chain = makeChain()
        XCTAssertEqual(chain.startingTier(for: .simpleAck), .localOllama)
        XCTAssertEqual(chain.startingTier(for: .statusQuery), .localOllama)
        XCTAssertEqual(chain.startingTier(for: .complex), .claudePrimary)
    }

    func testShouldFallbackToLocal() {
        let chain = makeChain()
        XCTAssertTrue(chain.shouldFallbackToLocal(DummyError(description: "Network error")))
        XCTAssertFalse(chain.shouldFallbackToLocal(DummyError(description: "auth failed 401")))
        XCTAssertFalse(chain.shouldFallbackToLocal(DummyError(description: "context overflow")))
    }
}
