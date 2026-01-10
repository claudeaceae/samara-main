import Foundation

/// Tracks context window usage and provides warnings at thresholds
/// Helps prevent context overflow and enables intelligent handoffs
final class ContextTracker {

    // MARK: - Types

    /// Context usage levels with associated behavior
    enum ContextLevel: Comparable {
        case green       // < 60%
        case yellow      // 60-69%
        case orange      // 70-79%
        case red         // 80-89%
        case critical    // >= 90%

        var emoji: String {
            switch self {
            case .green: return "🟢"
            case .yellow: return "🟡"
            case .orange: return "🟠"
            case .red: return "🔴"
            case .critical: return "⚠️"
            }
        }

        var warningMessage: String? {
            switch self {
            case .green, .yellow:
                return nil
            case .orange:
                return "Context at 70%. Consider wrapping up current task or preparing handoff."
            case .red:
                return "Context at 80%. Start preparing session handoff. Capture key state in ledger."
            case .critical:
                return "Context at 90%. Session handoff strongly recommended. Risk of context overflow."
            }
        }

        var shouldHandoff: Bool {
            self >= .critical
        }
    }

    /// Context metrics at a point in time
    struct ContextMetrics {
        let estimatedTokens: Int
        let maxTokens: Int
        let percentage: Double
        let level: ContextLevel
        let timestamp: Date

        var remaining: Int {
            max(0, maxTokens - estimatedTokens)
        }

        /// Generate a status line for display
        func statusLine() -> String {
            let pct = Int(percentage * 100)
            let bar = progressBar(percentage: percentage, width: 20)
            return "\(level.emoji) Context: \(bar) \(pct)% (\(formatTokens(estimatedTokens))/\(formatTokens(maxTokens)))"
        }

        /// Generate ASCII progress bar
        private func progressBar(percentage: Double, width: Int) -> String {
            let filled = Int(percentage * Double(width))
            let empty = width - filled
            return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
        }

        /// Format token counts for display
        private func formatTokens(_ tokens: Int) -> String {
            if tokens >= 1000 {
                return "\(tokens / 1000)K"
            }
            return "\(tokens)"
        }
    }

    // MARK: - Properties

    /// Maximum context window size (Claude 4 is ~200K)
    let maxTokens: Int

    /// Approximate tokens per character for estimation (~0.3 for English)
    private let tokensPerChar: Double = 0.30

    /// History of context measurements for trend analysis
    private var history: [ContextMetrics] = []

    /// Maximum history entries to keep
    private let maxHistorySize = 100

    // MARK: - Initialization

    /// Initialize context tracker
    /// - Parameter maxTokens: Maximum context window size (default 200K for Claude 4)
    init(maxTokens: Int = 200_000) {
        self.maxTokens = maxTokens
    }

    // MARK: - Token Estimation

    /// Estimate token count for a string
    /// Uses character-based heuristic (~0.3 tokens/char for English)
    func estimateTokens(_ text: String) -> Int {
        Int(Double(text.count) * tokensPerChar)
    }

    /// Estimate tokens for multiple strings
    func estimateTokens(_ texts: [String]) -> Int {
        texts.reduce(0) { $0 + estimateTokens($1) }
    }

    // MARK: - Level Calculation

    /// Determine context level from percentage
    func level(forPercentage percentage: Double) -> ContextLevel {
        switch percentage {
        case ..<0.60: return .green
        case 0.60..<0.70: return .yellow
        case 0.70..<0.80: return .orange
        case 0.80..<0.90: return .red
        default: return .critical
        }
    }

    // MARK: - Tracking

    /// Calculate current context metrics
    /// - Parameter currentContext: The full context string being sent to Claude
    /// - Returns: ContextMetrics with current state
    func calculateMetrics(for currentContext: String) -> ContextMetrics {
        let tokens = estimateTokens(currentContext)
        let percentage = Double(tokens) / Double(maxTokens)
        let contextLevel = level(forPercentage: percentage)

        let metrics = ContextMetrics(
            estimatedTokens: tokens,
            maxTokens: maxTokens,
            percentage: percentage,
            level: contextLevel,
            timestamp: Date()
        )

        // Add to history
        history.append(metrics)
        if history.count > maxHistorySize {
            history.removeFirst()
        }

        return metrics
    }

    /// Get the warning message if any for current level
    func warningMessage(for metrics: ContextMetrics) -> String? {
        metrics.level.warningMessage
    }

    /// Check if handoff is recommended
    func shouldTriggerHandoff(metrics: ContextMetrics) -> Bool {
        metrics.level.shouldHandoff
    }

    // MARK: - Trend Analysis

    /// Calculate context growth rate (tokens per minute)
    func growthRate() -> Double? {
        guard history.count >= 2 else { return nil }

        let recent = Array(history.suffix(10))
        guard let first = recent.first, let last = recent.last else { return nil }

        let tokenDelta = Double(last.estimatedTokens - first.estimatedTokens)
        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp) / 60.0  // minutes

        guard timeDelta > 0 else { return nil }
        return tokenDelta / timeDelta
    }

    /// Estimate time until context is full (in minutes)
    func estimatedTimeToFull(from metrics: ContextMetrics) -> Double? {
        guard let rate = growthRate(), rate > 0 else { return nil }

        let remainingTokens = Double(metrics.remaining)
        return remainingTokens / rate
    }

    // MARK: - Status Generation

    /// Generate a complete status block for inclusion in prompts
    func statusBlock(for context: String) -> String {
        let metrics = calculateMetrics(for: context)

        var lines: [String] = []
        lines.append(metrics.statusLine())

        if let warning = metrics.level.warningMessage {
            lines.append("⚠️ \(warning)")
        }

        if let timeToFull = estimatedTimeToFull(from: metrics), timeToFull < 60 {
            lines.append("📊 At current rate, context full in ~\(Int(timeToFull)) minutes")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a brief status for logging
    func briefStatus(for context: String) -> String {
        let metrics = calculateMetrics(for: context)
        return "\(metrics.level.emoji) \(Int(metrics.percentage * 100))% (\(metrics.estimatedTokens)/\(maxTokens) tokens)"
    }

    // MARK: - Session Metrics

    /// Reset tracking for a new session
    func resetForNewSession() {
        history.removeAll()
        log("Context tracker reset for new session", level: .debug, component: "ContextTracker")
    }

    /// Get summary of context usage during current session
    func sessionSummary() -> String {
        guard !history.isEmpty else {
            return "No context measurements recorded"
        }

        let peak = history.max(by: { $0.percentage < $1.percentage })!
        let avg = history.reduce(0.0) { $0 + $1.percentage } / Double(history.count)

        return """
            Session context summary:
            - Measurements: \(history.count)
            - Peak usage: \(Int(peak.percentage * 100))% (\(peak.estimatedTokens) tokens)
            - Average usage: \(Int(avg * 100))%
            """
    }
}
