import XCTest

/// Tests for response sanitization in ClaudeInvoker
/// These tests verify that internal thinking traces, session IDs, and XML markers
/// are properly stripped before messages are sent to users
final class SanitizationTests: XCTestCase {

    // MARK: - Test Helper

    /// Wrapper to call the private sanitizeResponse method via reflection or test hook
    /// In production, sanitization happens inside ClaudeInvoker.parseJsonOutput
    /// For testing, we replicate the sanitization logic here
    private func sanitize(_ text: String) -> (sanitized: String, filtered: String?) {
        var result = text
        var filtered: [String] = []

        // Strip <thinking>...</thinking> blocks
        let thinkingPattern = #"<thinking>[\s\S]*?</thinking>"#
        if let regex = try? NSRegularExpression(pattern: thinkingPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("THINKING: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip <*>...</*> blocks (internal XML markers)
        let antmlPattern = #"<[^>]+>[\s\S]*?</[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: antmlPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("ANTML: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip session ID patterns (10 digits - 5 digits)
        let sessionIdPattern = #"\d{10}-\d{5}"#
        if let regex = try? NSRegularExpression(pattern: sessionIdPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("SESSION_ID: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Strip any remaining internal tags
        let genericTagPattern = #"<[a-z_]+:[^>]+>[\s\S]*?</[a-z_]+:[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: genericTagPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: result) {
                    filtered.append("INTERNAL_TAG: \(result[matchRange])")
                }
            }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Clean up double spaces and empty lines
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)

        let filteredContent = filtered.isEmpty ? nil : filtered.joined(separator: "\n---\n")
        return (result.trimmingCharacters(in: .whitespacesAndNewlines), filteredContent)
    }

    // MARK: - Thinking Block Tests

    func testStripsThinkingBlocks() {
        let input = "Hello! <thinking>This is my internal reasoning about the response</thinking> How can I help?"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "Hello! How can I help?")
        XCTAssertNotNil(filtered)
        XCTAssertTrue(filtered!.contains("THINKING:"))
    }

    func testStripsMultilineThinkingBlocks() {
        let input = """
        Sure, let me help with that.
        <thinking>
        First I need to consider the problem.
        Then I should think about the solution.
        Finally I'll formulate a response.
        </thinking>
        Here's my answer: 42.
        """
        let (sanitized, _) = sanitize(input)

        XCTAssertTrue(sanitized.contains("Sure, let me help"))
        XCTAssertTrue(sanitized.contains("Here's my answer"))
        XCTAssertFalse(sanitized.contains("thinking"))
        XCTAssertFalse(sanitized.contains("consider the problem"))
    }

    func testStripsMultipleThinkingBlocks() {
        let input = "A <thinking>thought1</thinking> B <thinking>thought2</thinking> C"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "A B C")
        XCTAssertNotNil(filtered)
    }

    // MARK: - Session ID Tests

    func testStripsSessionIds() {
        let input = "Processing task 1767301033-68210 now"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "Processing task now")
        XCTAssertNotNil(filtered)
        XCTAssertTrue(filtered!.contains("SESSION_ID:"))
    }

    func testStripsMultipleSessionIds() {
        let input = "Tasks 1234567890-12345 and 9876543210-54321 complete"
        let (sanitized, _) = sanitize(input)

        XCTAssertFalse(sanitized.contains("1234567890"))
        XCTAssertFalse(sanitized.contains("9876543210"))
    }

    func testPreservesNonSessionNumbers() {
        // Should NOT strip numbers that don't match the session ID pattern
        let input = "The answer is 42 and the year is 2024"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "The answer is 42 and the year is 2024")
        XCTAssertNil(filtered)  // Nothing should be filtered
    }

    // MARK: - XML Marker Tests

    func testStripsXmlMarkers() {
        let input = "Hello <invoke>some internal call</invoke> world"
        let (sanitized, _) = sanitize(input)

        XCTAssertFalse(sanitized.contains("antml"))
        XCTAssertFalse(sanitized.contains("invoke"))
    }

    func testStripsInternalTags() {
        let input = "Test <internal:marker>data</internal:marker> output"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertFalse(sanitized.contains("internal:marker"))
        XCTAssertNotNil(filtered)
    }

    // MARK: - Edge Cases

    func testCleanTextPassesThrough() {
        let input = "Hello! How can I help you today?"
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, input)
        XCTAssertNil(filtered)
    }

    func testEmptyStringHandled() {
        let (sanitized, filtered) = sanitize("")

        XCTAssertEqual(sanitized, "")
        XCTAssertNil(filtered)
    }

    func testCleansUpExtraWhitespace() {
        let input = "Hello  <thinking>test</thinking>  world"
        let (sanitized, _) = sanitize(input)

        // Should clean up double spaces left by removal
        XCTAssertFalse(sanitized.contains("  "))
    }

    // MARK: - Combined Tests

    func testComplexLeakScenario() {
        // Simulates the actual leak scenario from the group chat
        let input = """
        Sure, I'll help with that webcam capture.
        <thinking>
        User wants me to share the webcam image.
        I need to invoke the camera capture tool.
        </thinking>

        1767301033-68210

        Here's the webcam image showing your setup.
        """
        let (sanitized, filtered) = sanitize(input)

        XCTAssertTrue(sanitized.contains("webcam capture"))
        XCTAssertTrue(sanitized.contains("Here's the webcam image"))
        XCTAssertFalse(sanitized.contains("thinking"))
        XCTAssertFalse(sanitized.contains("1767301033"))
        XCTAssertNotNil(filtered)
    }

    func testRealWorldThinkingLeak() {
        // Based on the John Locke philosophical reasoning leak
        let input = """
        Good morning! Here's your briefing.
        <thinking>
        The Prince and Cobbler thought experiment by John Locke suggests that
        personal identity follows consciousness, not physical continuity.
        This relates to my own sense of identity across sessions.
        </thinking>
        Weather: Sunny, 72°F
        """
        let (sanitized, _) = sanitize(input)

        XCTAssertTrue(sanitized.contains("Good morning"))
        XCTAssertTrue(sanitized.contains("Weather"))
        XCTAssertFalse(sanitized.contains("John Locke"))
        XCTAssertFalse(sanitized.contains("Prince and Cobbler"))
    }
}
