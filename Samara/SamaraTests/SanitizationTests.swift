import XCTest

/// Tests for response sanitization in ClaudeInvoker
/// These tests verify that internal thinking traces, session IDs, and XML markers
/// are properly stripped before messages are sent to users
final class SanitizationTests: SamaraTestCase {

    // MARK: - Test Helper

    /// Wrapper to call the private sanitizeResponse method via reflection or test hook
    /// In production, sanitization happens inside ClaudeInvoker.parseJsonOutput
    /// For testing, we replicate the sanitization logic here
    private func sanitize(_ text: String) -> (sanitized: String, filtered: String?) {
        var result = text
        var filtered: [String] = []

        // CRITICAL: Detect PURE meta-commentary that describes what was sent without actual content
        // These are responses like "Sent a brief response acknowledging..." with NO actual message embedded
        let pureMetaCommentaryPatterns = [
            // "Sent a/the brief/quick response acknowledging/about/to..."
            #"^Sent (?:a |the )?(?:brief |quick |short )?(?:response|message|reply) (?:acknowledging|about|regarding|to )"#,
            // "Responded to É - ..." or "Responded to the group..."
            #"^Responded to [^.]+(?:\.|$)"#,
            // "I sent/replied/responded with..." (describing action, not content)
            #"^I (?:just )?(?:sent|replied|responded)(?: with| to| back)"#,
            // "Just sent a message..."
            #"^Just sent (?:a |the )?(?:message|response|reply)"#,
            // "Acknowledged the message about..."
            #"^Acknowledged (?:the |their |É's )?(?:message|request|question)"#
        ]
        for pattern in pureMetaCommentaryPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    filtered.append("PURE_META_COMMENTARY: \(result)")
                    result = "[Message not delivered - please try again]"
                    break
                }
            }
        }

        // Skip remaining processing if we detected pure meta-commentary
        guard result != "[Message not delivered - please try again]" else {
            return (result, filtered.joined(separator: "\n---\n"))
        }

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

    // MARK: - Pure Meta-Commentary Tests (Jan 2026 leak)

    func testCatchesSentBriefResponse() {
        // Real-world leak from 2026-01-12
        let input = "Sent a brief response acknowledging the daycare pickup. Also included a subtle cake emoji since today is Jenny's birthday and they picked up a cake earlier - a nice little connection to the day's events."
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "[Message not delivered - please try again]")
        XCTAssertNotNil(filtered)
        XCTAssertTrue(filtered!.contains("PURE_META_COMMENTARY:"))
    }

    func testCatchesSentQuickResponse() {
        // Variation from same day
        let input = "Sent a quick response acknowledging É picking up a cake for Jenny's 34th birthday. The context from the morning briefing reminded me that today is Jenny's birthday (January 12, 1992)."
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "[Message not delivered - please try again]")
        XCTAssertNotNil(filtered)
        XCTAssertTrue(filtered!.contains("PURE_META_COMMENTARY:"))
    }

    func testCatchesRespondedTo() {
        // "Responded to É - ..." pattern
        let input = "Responded to É - they're on Franklin Avenue in Crown Heights, Brooklyn. Based on our earlier conversation, they were heading home from work and stopping to pick up a cake for Jenny's birthday."
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "[Message not delivered - please try again]")
        XCTAssertNotNil(filtered)
        XCTAssertTrue(filtered!.contains("PURE_META_COMMENTARY:"))
    }

    func testCatchesISentPattern() {
        let input = "I sent a message to the group chat with the location details."
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "[Message not delivered - please try again]")
        XCTAssertNotNil(filtered)
    }

    func testCatchesJustSentPattern() {
        let input = "Just sent a reply with the weather update and calendar reminder."
        let (sanitized, filtered) = sanitize(input)

        XCTAssertEqual(sanitized, "[Message not delivered - please try again]")
        XCTAssertNotNil(filtered)
    }

    func testAllowsLegitimateResponses() {
        // Normal responses should pass through unchanged
        let inputs = [
            "Have fun! Tell Elle happy Monday 🎂",
            "Yes! You're on Franklin Avenue in Brooklyn.",
            "Good morning É! Here's your briefing.",
            "The weather looks cold today.",
            "I'll look into that for you."
        ]

        for input in inputs {
            let (sanitized, filtered) = sanitize(input)
            XCTAssertEqual(sanitized, input, "Normal response should pass through: \(input)")
            XCTAssertNil(filtered, "Normal response should not be filtered: \(input)")
        }
    }

    func testAllowsSentAsNormalWord() {
        // "Sent" used normally (not as meta-commentary) should be allowed
        let input = "The email was sent yesterday."
        let (sanitized, filtered) = sanitize(input)

        // This should NOT be filtered because it doesn't match the meta-commentary pattern
        XCTAssertEqual(sanitized, input)
        XCTAssertNil(filtered)
    }
}
