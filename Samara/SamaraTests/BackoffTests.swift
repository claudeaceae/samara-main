import XCTest

final class BackoffTests: SamaraTestCase {

    private enum TestError: Error {
        case failure
    }

    func testShouldRetryStopsAtMax() {
        let config = Backoff.Config(maxRetries: 2, baseDelay: 0.0, maxDelay: 1.0, multiplier: 2.0, jitter: 0.0)
        let backoff = Backoff(config: config)

        XCTAssertTrue(backoff.shouldRetry)

        backoff.recordFailure()
        XCTAssertTrue(backoff.shouldRetry)

        backoff.recordFailure()
        XCTAssertFalse(backoff.shouldRetry)
    }

    func testCurrentDelayUsesExponentialWithoutJitter() {
        let config = Backoff.Config(maxRetries: 3, baseDelay: 1.0, maxDelay: 10.0, multiplier: 2.0, jitter: 0.0)
        let backoff = Backoff(config: config)

        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, 1.0)

        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, 2.0)

        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, 4.0)
    }

    func testExecuteRetriesUntilSuccess() throws {
        let config = Backoff.Config(maxRetries: 3, baseDelay: 0.0, maxDelay: 0.0, multiplier: 1.0, jitter: 0.0)
        let backoff = Backoff(config: config)
        var attempts = 0

        let result = try backoff.execute {
            attempts += 1
            if attempts < 3 {
                throw TestError.failure
            }
            return "ok"
        }

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(backoff.attemptCount, 2)
    }
}
