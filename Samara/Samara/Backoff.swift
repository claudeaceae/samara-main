import Foundation

/// Exponential backoff utility for retrying operations
///
/// Usage:
/// ```
/// let backoff = Backoff()
/// while backoff.shouldRetry {
///     do {
///         try someOperation()
///         break // Success
///     } catch {
///         backoff.recordFailure()
///         if backoff.shouldRetry {
///             Thread.sleep(forTimeInterval: backoff.currentDelay)
///         }
///     }
/// }
/// ```
final class Backoff {

    /// Configuration for backoff behavior
    struct Config {
        let maxRetries: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let multiplier: Double
        let jitter: Double  // 0.0 to 1.0, adds randomness to prevent thundering herd

        static let `default` = Config(
            maxRetries: 3,
            baseDelay: 1.0,
            maxDelay: 30.0,
            multiplier: 2.0,
            jitter: 0.1
        )

        static let aggressive = Config(
            maxRetries: 5,
            baseDelay: 0.5,
            maxDelay: 60.0,
            multiplier: 2.0,
            jitter: 0.2
        )

        static let gentle = Config(
            maxRetries: 3,
            baseDelay: 2.0,
            maxDelay: 10.0,
            multiplier: 1.5,
            jitter: 0.1
        )
    }

    private let config: Config
    private(set) var attemptCount: Int = 0
    private(set) var lastError: Error?

    init(config: Config = .default) {
        self.config = config
    }

    /// Whether another retry should be attempted
    var shouldRetry: Bool {
        return attemptCount < config.maxRetries
    }

    /// The current delay to wait before the next retry
    var currentDelay: TimeInterval {
        guard attemptCount > 0 else { return 0 }

        let exponentialDelay = config.baseDelay * pow(config.multiplier, Double(attemptCount - 1))
        let cappedDelay = min(exponentialDelay, config.maxDelay)

        // Add jitter
        let jitterRange = cappedDelay * config.jitter
        let jitter = Double.random(in: -jitterRange...jitterRange)

        return max(0, cappedDelay + jitter)
    }

    /// Record a failure and increment the attempt counter
    func recordFailure(error: Error? = nil) {
        attemptCount += 1
        lastError = error
    }

    /// Reset the backoff state
    func reset() {
        attemptCount = 0
        lastError = nil
    }

    /// Execute an operation with automatic retries and backoff
    /// - Parameters:
    ///   - operation: The operation to retry
    ///   - onRetry: Optional callback before each retry (for logging)
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries are exhausted
    func execute<T>(
        operation: () throws -> T,
        onRetry: ((Int, TimeInterval, Error) -> Void)? = nil
    ) throws -> T {
        reset()

        while true {
            do {
                return try operation()
            } catch {
                recordFailure(error: error)

                if shouldRetry {
                    let delay = currentDelay
                    onRetry?(attemptCount, delay, error)
                    Thread.sleep(forTimeInterval: delay)
                } else {
                    throw error
                }
            }
        }
    }

    /// Execute an async operation with automatic retries and backoff
    /// - Parameters:
    ///   - operation: The async operation to retry
    ///   - onRetry: Optional callback before each retry (for logging)
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries are exhausted
    @available(macOS 10.15, *)
    func executeAsync<T>(
        operation: () async throws -> T,
        onRetry: ((Int, TimeInterval, Error) -> Void)? = nil
    ) async throws -> T {
        reset()

        while true {
            do {
                return try await operation()
            } catch {
                recordFailure(error: error)

                if shouldRetry {
                    let delay = currentDelay
                    onRetry?(attemptCount, delay, error)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension Backoff {

    /// Create a backoff configured for database operations
    static func forDatabase() -> Backoff {
        return Backoff(config: Config(
            maxRetries: 5,
            baseDelay: 0.1,
            maxDelay: 5.0,
            multiplier: 2.0,
            jitter: 0.05
        ))
    }

    /// Create a backoff configured for network operations
    static func forNetwork() -> Backoff {
        return Backoff(config: Config(
            maxRetries: 3,
            baseDelay: 1.0,
            maxDelay: 30.0,
            multiplier: 2.0,
            jitter: 0.2
        ))
    }

    /// Create a backoff configured for AppleScript operations
    static func forAppleScript() -> Backoff {
        return Backoff(config: Config(
            maxRetries: 3,
            baseDelay: 1.0,
            maxDelay: 8.0,
            multiplier: 2.0,
            jitter: 0.1
        ))
    }
}
