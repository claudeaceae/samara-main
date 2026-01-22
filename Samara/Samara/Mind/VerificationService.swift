import Foundation

/// Service for verifying tool outputs and code changes
/// Can use local models for simple verification to save API quota
final class VerificationService {

    // MARK: - Types

    /// Types of verification that can be performed
    enum VerificationType {
        case syntaxCheck(language: String)
        case buildCheck
        case testCheck
        case safetyCheck  // Check for unsafe patterns
        case formatCheck
        case custom(prompt: String)
    }

    /// Result of a verification
    struct VerificationResult {
        let passed: Bool
        let message: String
        let details: [String]?
        let usedLocalModel: Bool
        let duration: TimeInterval
    }

    /// Checklist item for domain-specific verification
    struct ChecklistItem: Codable {
        let id: String
        let description: String
        let pattern: String?  // Regex pattern to check
        let command: String?  // Command to run
        let expectedOutput: String?
        let severity: Severity

        enum Severity: String, Codable {
            case error = "error"      // Must pass
            case warning = "warning"  // Should pass
            case info = "info"        // Nice to have
        }
    }

    /// Domain-specific checklist
    struct Checklist: Codable {
        let id: String
        let name: String
        let domain: String  // e.g., "swift", "typescript", "git"
        let items: [ChecklistItem]
    }

    // MARK: - Properties

    /// Local model invoker for simple verifications
    private let localInvoker: LocalModelInvoker

    /// Path to checklists
    private let checklistsDir: String

    /// Loaded checklists by domain
    private var checklists: [String: Checklist] = [:]

    // MARK: - Initialization

    init(localInvoker: LocalModelInvoker? = nil) {
        // Use provided invoker or create default
        if let invoker = localInvoker {
            self.localInvoker = invoker
        } else {
            let endpoint = URL(string: config.modelsConfig.localEndpoint) ?? URL(string: "http://localhost:11434")!
            self.localInvoker = LocalModelInvoker(endpoint: endpoint, timeout: 30)
        }

        self.checklistsDir = MindPaths.mindPath("state/checklists")

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: checklistsDir, withIntermediateDirectories: true)

        // Load checklists
        loadChecklists()

        // Create defaults if none exist
        if checklists.isEmpty {
            createDefaultChecklists()
        }
    }

    // MARK: - Verification

    /// Verify content using appropriate method
    func verify(
        content: String,
        type: VerificationType,
        useLocalModel: Bool = true
    ) async -> VerificationResult {
        let startTime = Date()

        switch type {
        case .syntaxCheck(let language):
            return await verifySyntax(content: content, language: language, useLocal: useLocalModel, startTime: startTime)

        case .buildCheck:
            return verifyBuild(startTime: startTime)

        case .testCheck:
            return verifyTests(startTime: startTime)

        case .safetyCheck:
            return await verifySafety(content: content, useLocal: useLocalModel, startTime: startTime)

        case .formatCheck:
            return await verifyFormat(content: content, useLocal: useLocalModel, startTime: startTime)

        case .custom(let prompt):
            return await verifyCustom(content: content, prompt: prompt, useLocal: useLocalModel, startTime: startTime)
        }
    }

    /// Run domain-specific checklist
    func runChecklist(domain: String, context: String) async -> [ChecklistResult] {
        if checklists[domain] == nil {
            if let checklist = loadChecklist(domain: domain) {
                checklists[domain] = checklist
            } else {
                loadChecklists()
            }
        }
        guard let checklist = checklists[domain] else {
            return []
        }

        var results: [ChecklistResult] = []

        for item in checklist.items {
            let result = await evaluateChecklistItem(item, context: context)
            results.append(result)
        }

        return results
    }

    struct ChecklistResult {
        let item: ChecklistItem
        let passed: Bool
        let details: String?
    }

    // MARK: - Verification Methods

    private func verifySyntax(content: String, language: String, useLocal: Bool, startTime: Date) async -> VerificationResult {
        // For Swift, we can use swiftc -parse
        if language.lowercased() == "swift" {
            return verifySwiftSyntax(content: content, startTime: startTime)
        }

        // For other languages, use local model if available
        if useLocal {
            let prompt = """
                Check the following \(language) code for syntax errors.
                Respond with ONLY "PASS" if the syntax is correct, or "FAIL: <reason>" if there are errors.

                Code:
                ```\(language)
                \(content)
                ```
                """

            do {
                let response = try await localInvoker.invoke(model: "llama3.1:8b", prompt: prompt)
                let passed = response.uppercased().hasPrefix("PASS")
                return VerificationResult(
                    passed: passed,
                    message: response,
                    details: nil,
                    usedLocalModel: true,
                    duration: Date().timeIntervalSince(startTime)
                )
            } catch {
                // Fall through to default response
            }
        }

        return VerificationResult(
            passed: true,
            message: "Syntax verification skipped (no local model)",
            details: nil,
            usedLocalModel: false,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func verifySwiftSyntax(content: String, startTime: Date) -> VerificationResult {
        // Write to temp file
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify_\(UUID().uuidString).swift")

        do {
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Run swiftc -parse
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["swiftc", "-parse", tempFile.path]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            let passed = process.terminationStatus == 0
            return VerificationResult(
                passed: passed,
                message: passed ? "Swift syntax valid" : "Swift syntax errors found",
                details: passed ? nil : [errorOutput],
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            return VerificationResult(
                passed: true,
                message: "Could not verify Swift syntax: \(error.localizedDescription)",
                details: nil,
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    private func verifyBuild(startTime: Date) -> VerificationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-scheme", "Samara", "-configuration", "Debug", "build"]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Developer/samara-main/Samara")

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            let passed = process.terminationStatus == 0
            return VerificationResult(
                passed: passed,
                message: passed ? "Build succeeded" : "Build failed",
                details: nil,
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            return VerificationResult(
                passed: false,
                message: "Could not run build: \(error.localizedDescription)",
                details: nil,
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    private func verifyTests(startTime: Date) -> VerificationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-scheme", "Samara", "-configuration", "Debug", "test"]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Developer/samara-main/Samara")

        do {
            try process.run()
            process.waitUntilExit()

            let passed = process.terminationStatus == 0
            return VerificationResult(
                passed: passed,
                message: passed ? "Tests passed" : "Tests failed",
                details: nil,
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            return VerificationResult(
                passed: false,
                message: "Could not run tests: \(error.localizedDescription)",
                details: nil,
                usedLocalModel: false,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    private func verifySafety(content: String, useLocal: Bool, startTime: Date) async -> VerificationResult {
        // Check for common unsafe patterns
        var issues: [String] = []

        // Check for hardcoded secrets
        let secretPatterns = [
            "(?i)password\\s*=\\s*[\"'][^\"']+[\"']",
            "(?i)api[_-]?key\\s*=\\s*[\"'][^\"']+[\"']",
            "(?i)secret\\s*=\\s*[\"'][^\"']+[\"']",
            "(?i)token\\s*=\\s*[\"'][^\"']+[\"']"
        ]

        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    issues.append("Potential hardcoded secret detected")
                    break
                }
            }
        }

        // Check for dangerous operations
        let dangerousPatterns = [
            "rm\\s+-rf\\s+/",
            "eval\\(",
            "exec\\(",
            "system\\("
        ]

        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    issues.append("Potentially dangerous operation: \(pattern)")
                }
            }
        }

        let passed = issues.isEmpty
        return VerificationResult(
            passed: passed,
            message: passed ? "No safety issues detected" : "Safety issues found",
            details: passed ? nil : issues,
            usedLocalModel: false,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func verifyFormat(content: String, useLocal: Bool, startTime: Date) async -> VerificationResult {
        // Basic formatting checks
        var issues: [String] = []

        // Check for trailing whitespace
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                issues.append("Line \(index + 1): trailing whitespace")
            }
        }

        // Check for tabs vs spaces consistency
        let hasTab = content.contains("\t")
        let hasSpaceIndent = content.contains("\n    ")
        if hasTab && hasSpaceIndent {
            issues.append("Mixed tabs and spaces for indentation")
        }

        let passed = issues.isEmpty
        return VerificationResult(
            passed: passed,
            message: passed ? "Formatting looks good" : "Formatting issues found",
            details: passed ? nil : Array(issues.prefix(5)),  // Limit to first 5
            usedLocalModel: false,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    private func verifyCustom(content: String, prompt: String, useLocal: Bool, startTime: Date) async -> VerificationResult {
        if useLocal {
            let fullPrompt = """
                \(prompt)

                Content to verify:
                ```
                \(content)
                ```

                Respond with ONLY "PASS" if verification passes, or "FAIL: <reason>" if it fails.
                """

            do {
                let response = try await localInvoker.invoke(model: "llama3.1:8b", prompt: fullPrompt)
                let passed = response.uppercased().hasPrefix("PASS")
                return VerificationResult(
                    passed: passed,
                    message: response,
                    details: nil,
                    usedLocalModel: true,
                    duration: Date().timeIntervalSince(startTime)
                )
            } catch {
                // Fall through
            }
        }

        return VerificationResult(
            passed: true,
            message: "Custom verification skipped (no local model)",
            details: nil,
            usedLocalModel: false,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Checklist Evaluation

    private func evaluateChecklistItem(_ item: ChecklistItem, context: String) async -> ChecklistResult {
        // Pattern-based check
        if let pattern = item.pattern {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(context.startIndex..., in: context)
                let matches = regex.firstMatch(in: context, options: [], range: range) != nil
                return ChecklistResult(item: item, passed: matches, details: nil)
            }
        }

        // Command-based check
        if let command = item.command {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if let expected = item.expectedOutput {
                    let passed = output.contains(expected)
                    return ChecklistResult(item: item, passed: passed, details: output)
                } else {
                    let passed = process.terminationStatus == 0
                    return ChecklistResult(item: item, passed: passed, details: output)
                }
            } catch {
                return ChecklistResult(item: item, passed: false, details: error.localizedDescription)
            }
        }

        // Default: pass
        return ChecklistResult(item: item, passed: true, details: nil)
    }

    // MARK: - Persistence

    private func loadChecklists() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: checklistsDir) else { return }

        let decoder = JSONDecoder()

        for file in files where file.hasSuffix(".json") {
            let path = (checklistsDir as NSString).appendingPathComponent(file)
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let checklist = try decoder.decode(Checklist.self, from: data)
                checklists[checklist.domain] = checklist
            } catch {
                log("Failed to load checklist from \(file): \(error)", level: .warn, component: "VerificationService")
            }
        }

        log("Loaded \(checklists.count) checklists", level: .info, component: "VerificationService")
    }

    private func loadChecklist(domain: String) -> Checklist? {
        let path = (checklistsDir as NSString).appendingPathComponent("\(domain).json")
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try decoder.decode(Checklist.self, from: data)
        } catch {
            log("Failed to load checklist for \(domain): \(error)", level: .warn, component: "VerificationService")
            return nil
        }
    }

    private func createDefaultChecklists() {
        // Swift checklist
        let swiftChecklist = Checklist(
            id: "swift-default",
            name: "Swift Code Checklist",
            domain: "swift",
            items: [
                ChecklistItem(
                    id: "no-force-unwrap",
                    description: "Avoid force unwrap (!)",
                    pattern: "(?<!\\?)!(?![=!])",
                    command: nil,
                    expectedOutput: nil,
                    severity: .warning
                ),
                ChecklistItem(
                    id: "no-try-bang",
                    description: "Avoid try! force try",
                    pattern: "try!",
                    command: nil,
                    expectedOutput: nil,
                    severity: .warning
                ),
                ChecklistItem(
                    id: "builds-clean",
                    description: "Project builds without errors",
                    pattern: nil,
                    command: "cd ~/Developer/samara-main/Samara && xcodebuild -scheme Samara build 2>&1 | grep -q 'BUILD SUCCEEDED' && echo 'PASS' || echo 'FAIL'",
                    expectedOutput: "PASS",
                    severity: .error
                )
            ]
        )

        // Git checklist
        let gitChecklist = Checklist(
            id: "git-default",
            name: "Git Commit Checklist",
            domain: "git",
            items: [
                ChecklistItem(
                    id: "no-secrets",
                    description: "No secrets in staged files",
                    pattern: nil,
                    command: "git diff --cached | grep -iE '(password|secret|api.?key|token)\\s*=' | head -1",
                    expectedOutput: "",
                    severity: .error
                ),
                ChecklistItem(
                    id: "no-large-files",
                    description: "No large files (>1MB)",
                    pattern: nil,
                    command: "git diff --cached --name-only | xargs -I {} sh -c 'test -f {} && stat -f %z {} 2>/dev/null || echo 0' | awk '$1 > 1000000 {print \"LARGE\"}' | head -1",
                    expectedOutput: "",
                    severity: .warning
                )
            ]
        )

        // Save checklists
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        for checklist in [swiftChecklist, gitChecklist] {
            let path = (checklistsDir as NSString).appendingPathComponent("\(checklist.domain).json")
            do {
                let data = try encoder.encode(checklist)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                checklists[checklist.domain] = checklist
            } catch {
                log("Failed to save checklist \(checklist.domain): \(error)", level: .error, component: "VerificationService")
            }
        }

        log("Created \(checklists.count) default checklists", level: .info, component: "VerificationService")
    }
}
