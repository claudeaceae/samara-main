import Foundation

/// Loads and parses ritual configuration for different wake types
/// Provides context-specific guidance based on time of day
final class RitualLoader {

    // MARK: - Types

    /// Types of wake rituals
    enum WakeType: String, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case emergency = "Emergency"
        case dream = "Dream"

        /// Determine wake type from current time
        static func fromTime(_ date: Date = Date()) -> WakeType {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)

            switch hour {
            case 3...4:
                return .dream
            case 5...11:
                return .morning
            case 12...16:
                return .afternoon
            case 17...23, 0...2:
                return .evening
            default:
                return .morning
            }
        }

        var displayName: String {
            rawValue
        }

        var sectionHeader: String {
            "## \(rawValue)"
        }
    }

    /// Parsed ritual section
    struct RitualSection {
        let wakeType: WakeType
        let contextToLoad: [String]
        let checks: [String]
        let behavior: [String]
        let tone: String
        let maxDuration: String
        let rawContent: String
    }

    // MARK: - Properties

    /// Path to ritual configuration
    private let ritualPath: String

    /// Cached ritual content
    private var cachedContent: String?

    /// Cached parsed sections
    private var cachedSections: [WakeType: RitualSection] = [:]

    /// Last modification time of ritual file
    private var lastModified: Date?

    // MARK: - Initialization

    init(mindPath: String? = nil) {
        let basePath = mindPath ?? MindPaths.mindPath()

        self.ritualPath = (basePath as NSString).appendingPathComponent("self/ritual.md")

        // Load and parse
        loadRitual()
    }

    // MARK: - Public API

    /// Get ritual section for current time
    func getCurrentRitual() -> RitualSection? {
        let wakeType = WakeType.fromTime()
        return getRitual(for: wakeType)
    }

    /// Get ritual section for specific wake type
    func getRitual(for wakeType: WakeType) -> RitualSection? {
        reloadIfNeeded()
        return cachedSections[wakeType]
    }

    /// Get context-specific prompt addition for a wake type
    func getContextPrompt(for wakeType: WakeType) -> String {
        guard let section = getRitual(for: wakeType) else {
            return ""
        }

        var lines: [String] = []

        lines.append("## Wake Type: \(wakeType.displayName)")
        lines.append("")

        if !section.contextToLoad.isEmpty {
            lines.append("### Context Focus")
            for item in section.contextToLoad {
                lines.append("- \(item)")
            }
            lines.append("")
        }

        if !section.checks.isEmpty {
            lines.append("### Checks to Perform")
            for check in section.checks {
                lines.append("- [ ] \(check)")
            }
            lines.append("")
        }

        if !section.behavior.isEmpty {
            lines.append("### Behavioral Guidelines")
            for behavior in section.behavior {
                lines.append("- \(behavior)")
            }
            lines.append("")
        }

        if !section.tone.isEmpty {
            lines.append("### Tone")
            lines.append(section.tone)
            lines.append("")
        }

        if !section.maxDuration.isEmpty {
            lines.append("### Time Budget")
            lines.append("Maximum duration: \(section.maxDuration)")
        }

        return lines.joined(separator: "\n")
    }

    /// Get all wake types that have ritual definitions
    func getDefinedWakeTypes() -> [WakeType] {
        reloadIfNeeded()
        return Array(cachedSections.keys).sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Loading and Parsing

    private func loadRitual() {
        guard FileManager.default.fileExists(atPath: ritualPath) else {
            log("Ritual file not found at \(ritualPath)", level: .warn, component: "RitualLoader")
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: ritualPath)
            lastModified = attributes[.modificationDate] as? Date

            cachedContent = try String(contentsOfFile: ritualPath, encoding: .utf8)
            parseRitual()

            log("Loaded ritual with \(cachedSections.count) sections", level: .info, component: "RitualLoader")
        } catch {
            log("Failed to load ritual: \(error)", level: .error, component: "RitualLoader")
        }
    }

    private func reloadIfNeeded() {
        guard FileManager.default.fileExists(atPath: ritualPath) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: ritualPath)
            let currentModified = attributes[.modificationDate] as? Date

            if let lastMod = lastModified, let currentMod = currentModified {
                if currentMod > lastMod {
                    loadRitual()
                }
            }
        } catch {
            // Ignore
        }
    }

    private func parseRitual() {
        guard let content = cachedContent else { return }

        cachedSections = [:]

        // Split by ## headers
        let sections = content.components(separatedBy: "\n## ")

        for section in sections {
            guard !section.isEmpty else { continue }

            // Find wake type from section header
            let firstLine = section.components(separatedBy: "\n").first ?? ""

            var matchedType: WakeType?
            for wakeType in WakeType.allCases {
                if firstLine.lowercased().contains(wakeType.rawValue.lowercased()) {
                    matchedType = wakeType
                    break
                }
            }

            guard let wakeType = matchedType else { continue }

            // Parse section content
            let ritualSection = parseSection(content: section, wakeType: wakeType)
            cachedSections[wakeType] = ritualSection
        }
    }

    private func parseSection(content: String, wakeType: WakeType) -> RitualSection {
        var contextToLoad: [String] = []
        var checks: [String] = []
        var behavior: [String] = []
        var tone = ""
        var maxDuration = ""

        var currentSubsection = ""

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect subsection headers
            if trimmed.hasPrefix("### ") {
                let header = trimmed.dropFirst(4).lowercased()
                if header.contains("context") {
                    currentSubsection = "context"
                } else if header.contains("check") {
                    currentSubsection = "checks"
                } else if header.contains("behavior") || header.contains("process") {
                    currentSubsection = "behavior"
                } else if header.contains("tone") {
                    currentSubsection = "tone"
                } else if header.contains("duration") || header.contains("time") {
                    currentSubsection = "duration"
                } else {
                    currentSubsection = ""
                }
                continue
            }

            // Skip empty lines and dividers
            if trimmed.isEmpty || trimmed.hasPrefix("---") {
                continue
            }

            // Parse list items
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                    .replacingOccurrences(of: "[ ] ", with: "")
                    .replacingOccurrences(of: "[x] ", with: "")

                switch currentSubsection {
                case "context":
                    contextToLoad.append(item)
                case "checks":
                    checks.append(item)
                case "behavior":
                    behavior.append(item)
                default:
                    break
                }
            } else if currentSubsection == "tone" && !trimmed.hasPrefix("#") {
                tone = trimmed
            } else if currentSubsection == "duration" && !trimmed.hasPrefix("#") {
                // Extract duration value
                if let match = trimmed.range(of: #"\d+\s*(minutes?|min|m|hours?|hr|h)"#, options: .regularExpression) {
                    maxDuration = String(trimmed[match])
                } else {
                    maxDuration = trimmed
                }
            }
        }

        return RitualSection(
            wakeType: wakeType,
            contextToLoad: contextToLoad,
            checks: checks,
            behavior: behavior,
            tone: tone,
            maxDuration: maxDuration,
            rawContent: content
        )
    }
}
