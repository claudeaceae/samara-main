import XCTest

final class ContextTrackerTests: SamaraTestCase {

    func testLevelBoundaries() {
        let tracker = ContextTracker(maxTokens: 100)

        XCTAssertEqual(tracker.level(forPercentage: 0.59), .green)
        XCTAssertEqual(tracker.level(forPercentage: 0.60), .yellow)
        XCTAssertEqual(tracker.level(forPercentage: 0.70), .orange)
        XCTAssertEqual(tracker.level(forPercentage: 0.80), .red)
        XCTAssertEqual(tracker.level(forPercentage: 0.90), .critical)
    }

    func testCalculateMetricsAndWarnings() {
        let tracker = ContextTracker(maxTokens: 100)
        let orangeText = String(repeating: "a", count: 250) // 75 tokens
        let orangeMetrics = tracker.calculateMetrics(for: orangeText)

        XCTAssertEqual(orangeMetrics.level, .orange)
        XCTAssertNotNil(tracker.warningMessage(for: orangeMetrics))
        XCTAssertFalse(tracker.shouldTriggerHandoff(metrics: orangeMetrics))

        let criticalText = String(repeating: "b", count: 300) // 90 tokens
        let criticalMetrics = tracker.calculateMetrics(for: criticalText)

        XCTAssertEqual(criticalMetrics.level, .critical)
        XCTAssertTrue(tracker.shouldTriggerHandoff(metrics: criticalMetrics))
    }

    func testStatusBlockIncludesWarning() {
        let tracker = ContextTracker(maxTokens: 100)
        let orangeText = String(repeating: "c", count: 250)
        let status = tracker.statusBlock(for: orangeText)

        XCTAssertTrue(status.contains("Context:"))
        XCTAssertTrue(status.contains("Consider wrapping up"))
    }

    func testSessionSummaryAndReset() {
        let tracker = ContextTracker(maxTokens: 100)

        XCTAssertEqual(tracker.sessionSummary(), "No context measurements recorded")

        _ = tracker.calculateMetrics(for: String(repeating: "d", count: 120))
        XCTAssertTrue(tracker.sessionSummary().contains("Measurements"))

        tracker.resetForNewSession()
        XCTAssertEqual(tracker.sessionSummary(), "No context measurements recorded")
    }

    func testGrowthRateAndEstimate() {
        let tracker = ContextTracker(maxTokens: 100)
        _ = tracker.calculateMetrics(for: String(repeating: "e", count: 100))
        Thread.sleep(forTimeInterval: 0.01)
        let latest = tracker.calculateMetrics(for: String(repeating: "f", count: 200))

        XCTAssertNotNil(tracker.growthRate())
        XCTAssertNotNil(tracker.estimatedTimeToFull(from: latest))
    }
}
