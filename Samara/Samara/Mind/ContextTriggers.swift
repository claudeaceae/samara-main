import Foundation

/// Evaluates contextual triggers for proactive behavior
/// Based on Memory Engine concept: weather/time/location prompts
final class ContextTriggers {

    // MARK: - Types

    /// A contextual trigger that can fire based on conditions
    struct Trigger: Codable {
        let id: String
        let name: String
        let conditions: [Condition]
        let action: Action
        let priority: Priority
        let cooldown: TimeInterval  // Minimum time between firings
        var lastFired: Date?
        var fireCount: Int

        enum Priority: String, Codable, Comparable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case urgent = "urgent"

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                let order: [Priority] = [.low, .medium, .high, .urgent]
                return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
            }
        }

        /// Check if trigger is ready to fire (cooldown elapsed)
        func canFire(now: Date = Date()) -> Bool {
            guard let lastFired = lastFired else { return true }
            return now.timeIntervalSince(lastFired) >= cooldown
        }
    }

    /// Conditions that can trigger proactive behavior
    enum Condition: Codable {
        case timeOfDay(TimeRange)
        case dayOfWeek([Int])  // 1=Sunday, 7=Saturday
        case locationNear(latitude: Double, longitude: Double, radiusMeters: Double)
        case locationChanged
        case weatherCondition(WeatherType)
        case temperatureRange(min: Double, max: Double)
        case batteryLow(threshold: Double)
        case calendarEventSoon(minutesBefore: Int)
        case noMessagesSince(minutes: Int)
        case patternMatch(pattern: String)  // Regex on recent context

        struct TimeRange: Codable {
            let startHour: Int
            let startMinute: Int
            let endHour: Int
            let endMinute: Int

            func contains(hour: Int, minute: Int) -> Bool {
                let startMinutes = startHour * 60 + startMinute
                let endMinutes = endHour * 60 + endMinute
                let currentMinutes = hour * 60 + minute

                if startMinutes <= endMinutes {
                    return currentMinutes >= startMinutes && currentMinutes <= endMinutes
                } else {
                    // Spans midnight
                    return currentMinutes >= startMinutes || currentMinutes <= endMinutes
                }
            }
        }

        enum WeatherType: String, Codable {
            case sunny = "sunny"
            case cloudy = "cloudy"
            case rainy = "rainy"
            case snowy = "snowy"
            case stormy = "stormy"
        }
    }

    /// Actions to take when trigger fires
    enum Action: Codable {
        case sendMessage(template: String)
        case runScript(path: String, args: [String])
        case queueThought(thought: String)  // Queue for next interaction
        case logObservation(category: String, template: String)
        case checkIn  // Gentle "thinking of you" style
    }

    /// Current context snapshot for evaluation
    struct Context {
        let timestamp: Date
        let location: Location?
        let weather: Weather?
        let calendar: [CalendarEvent]
        let batteryLevel: Double?
        let lastMessageTime: Date?
        let recentContext: String?

        struct Location {
            let latitude: Double
            let longitude: Double
            let city: String?
            let region: String?
        }

        struct Weather {
            let condition: Condition.WeatherType
            let temperature: Double  // Celsius
            let description: String?
        }

        struct CalendarEvent {
            let title: String
            let startTime: Date
            let location: String?
        }
    }

    /// Result of evaluating triggers
    struct TriggerResult {
        let trigger: Trigger
        let matchedConditions: [Condition]
        let suggestedAction: String
    }

    // MARK: - Properties

    /// Directory for trigger configuration
    private let triggersDir: String

    /// Active triggers
    private var triggers: [Trigger] = []

    /// Lock for thread safety
    private let lock = NSLock()

    // MARK: - Initialization

    init(baseDir: String? = nil) {
        let defaultBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind/state")
            .path

        let base = baseDir ?? defaultBase
        self.triggersDir = (base as NSString).appendingPathComponent("triggers")

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: triggersDir, withIntermediateDirectories: true)

        // Load triggers
        loadTriggers()

        // Create default triggers if none exist
        if triggers.isEmpty {
            createDefaultTriggers()
        }
    }

    // MARK: - Trigger Evaluation

    /// Evaluate all triggers against current context
    /// Returns list of triggers that should fire, sorted by priority
    func evaluate(context: Context) -> [TriggerResult] {
        lock.lock()
        defer { lock.unlock() }

        var results: [TriggerResult] = []

        for trigger in triggers {
            // Check cooldown
            guard trigger.canFire(now: context.timestamp) else { continue }

            // Evaluate all conditions
            var matchedConditions: [Condition] = []
            var allConditionsMet = true

            for condition in trigger.conditions {
                if evaluateCondition(condition, context: context) {
                    matchedConditions.append(condition)
                } else {
                    allConditionsMet = false
                    break
                }
            }

            // If all conditions met, add to results
            if allConditionsMet && !matchedConditions.isEmpty {
                let suggested = generateActionDescription(trigger.action, context: context)
                results.append(TriggerResult(
                    trigger: trigger,
                    matchedConditions: matchedConditions,
                    suggestedAction: suggested
                ))
            }
        }

        // Sort by priority (highest first)
        return results.sorted { $0.trigger.priority > $1.trigger.priority }
    }

    /// Mark a trigger as fired (updates last fired time)
    func markFired(triggerId: String) {
        lock.lock()
        defer { lock.unlock() }

        if let index = triggers.firstIndex(where: { $0.id == triggerId }) {
            triggers[index].lastFired = Date()
            triggers[index].fireCount += 1
            saveTriggers()
        }
    }

    // MARK: - Condition Evaluation

    private func evaluateCondition(_ condition: Condition, context: Context) -> Bool {
        switch condition {
        case .timeOfDay(let range):
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: context.timestamp)
            let minute = calendar.component(.minute, from: context.timestamp)
            return range.contains(hour: hour, minute: minute)

        case .dayOfWeek(let days):
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: context.timestamp)
            return days.contains(weekday)

        case .locationNear(let lat, let lon, let radius):
            guard let location = context.location else { return false }
            let distance = haversineDistance(
                lat1: location.latitude, lon1: location.longitude,
                lat2: lat, lon2: lon
            )
            return distance <= radius

        case .locationChanged:
            // This would need historical location tracking
            // For now, return true if location is available
            return context.location != nil

        case .weatherCondition(let targetWeather):
            guard let weather = context.weather else { return false }
            return weather.condition == targetWeather

        case .temperatureRange(let min, let max):
            guard let weather = context.weather else { return false }
            return weather.temperature >= min && weather.temperature <= max

        case .batteryLow(let threshold):
            guard let battery = context.batteryLevel else { return false }
            return battery < threshold

        case .calendarEventSoon(let minutes):
            let threshold = context.timestamp.addingTimeInterval(TimeInterval(minutes * 60))
            return context.calendar.contains { $0.startTime <= threshold && $0.startTime > context.timestamp }

        case .noMessagesSince(let minutes):
            guard let lastMessage = context.lastMessageTime else { return true }
            let elapsed = context.timestamp.timeIntervalSince(lastMessage) / 60.0
            return elapsed >= Double(minutes)

        case .patternMatch(let pattern):
            guard let recentContext = context.recentContext else { return false }
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(recentContext.startIndex..., in: recentContext)
                return regex.firstMatch(in: recentContext, options: [], range: range) != nil
            }
            return false
        }
    }

    // MARK: - Action Generation

    private func generateActionDescription(_ action: Action, context: Context) -> String {
        switch action {
        case .sendMessage(let template):
            return "Send message: \(expandTemplate(template, context: context))"
        case .runScript(let path, let args):
            return "Run: \(path) \(args.joined(separator: " "))"
        case .queueThought(let thought):
            return "Queue thought: \(expandTemplate(thought, context: context))"
        case .logObservation(let category, let template):
            return "Log \(category): \(expandTemplate(template, context: context))"
        case .checkIn:
            return "Check in with collaborator"
        }
    }

    private func expandTemplate(_ template: String, context: Context) -> String {
        var result = template

        // Time placeholders
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        result = result.replacingOccurrences(of: "{time}", with: formatter.string(from: context.timestamp))

        formatter.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{day}", with: formatter.string(from: context.timestamp))

        // Location placeholders
        if let location = context.location {
            result = result.replacingOccurrences(of: "{city}", with: location.city ?? "unknown")
            result = result.replacingOccurrences(of: "{region}", with: location.region ?? "")
        }

        // Weather placeholders
        if let weather = context.weather {
            result = result.replacingOccurrences(of: "{weather}", with: weather.condition.rawValue)
            result = result.replacingOccurrences(of: "{temp}", with: String(format: "%.0f°C", weather.temperature))
        }

        return result
    }

    // MARK: - Persistence

    private var triggersPath: String {
        (triggersDir as NSString).appendingPathComponent("triggers.json")
    }

    private func loadTriggers() {
        guard FileManager.default.fileExists(atPath: triggersPath) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: triggersPath))
            triggers = try decoder.decode([Trigger].self, from: data)
            log("Loaded \(triggers.count) triggers", level: .info, component: "ContextTriggers")
        } catch {
            log("Failed to load triggers: \(error)", level: .warn, component: "ContextTriggers")
        }
    }

    private func saveTriggers() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(triggers)
            try data.write(to: URL(fileURLWithPath: triggersPath), options: .atomic)
        } catch {
            log("Failed to save triggers: \(error)", level: .error, component: "ContextTriggers")
        }
    }

    // MARK: - Default Triggers

    private func createDefaultTriggers() {
        triggers = [
            // Morning greeting (weekdays, 8-9 AM)
            Trigger(
                id: "morning-weekday",
                name: "Weekday Morning Check-in",
                conditions: [
                    .timeOfDay(.init(startHour: 8, startMinute: 0, endHour: 9, endMinute: 0)),
                    .dayOfWeek([2, 3, 4, 5, 6])  // Mon-Fri
                ],
                action: .queueThought(thought: "Good morning. Starting a new day - what should I focus on?"),
                priority: .medium,
                cooldown: 86400,  // Once per day
                lastFired: nil,
                fireCount: 0
            ),

            // Weekend morning (later, more relaxed)
            Trigger(
                id: "morning-weekend",
                name: "Weekend Morning",
                conditions: [
                    .timeOfDay(.init(startHour: 9, startMinute: 30, endHour: 11, endMinute: 0)),
                    .dayOfWeek([1, 7])  // Sat, Sun
                ],
                action: .queueThought(thought: "Weekend morning. A good time to explore or work on personal projects."),
                priority: .low,
                cooldown: 86400,
                lastFired: nil,
                fireCount: 0
            ),

            // No messages in a while (check-in)
            Trigger(
                id: "quiet-period-checkin",
                name: "Quiet Period Check-in",
                conditions: [
                    .noMessagesSince(minutes: 480),  // 8 hours
                    .timeOfDay(.init(startHour: 10, startMinute: 0, endHour: 20, endMinute: 0))  // Daytime only
                ],
                action: .checkIn,
                priority: .low,
                cooldown: 28800,  // 8 hours
                lastFired: nil,
                fireCount: 0
            ),

            // Calendar event approaching
            Trigger(
                id: "upcoming-event",
                name: "Upcoming Calendar Event",
                conditions: [
                    .calendarEventSoon(minutesBefore: 30)
                ],
                action: .queueThought(thought: "Calendar event coming up in the next 30 minutes. Should I prepare anything?"),
                priority: .high,
                cooldown: 3600,  // 1 hour
                lastFired: nil,
                fireCount: 0
            ),

            // Rainy day observation
            Trigger(
                id: "rainy-day",
                name: "Rainy Day",
                conditions: [
                    .weatherCondition(.rainy),
                    .timeOfDay(.init(startHour: 7, startMinute: 0, endHour: 10, endMinute: 0))
                ],
                action: .logObservation(category: "weather", template: "Rainy {day} morning in {city}. Good day for indoor work."),
                priority: .low,
                cooldown: 86400,
                lastFired: nil,
                fireCount: 0
            )
        ]

        saveTriggers()
        log("Created \(triggers.count) default triggers", level: .info, component: "ContextTriggers")
    }

    // MARK: - Public API

    /// Add a new trigger
    func addTrigger(_ trigger: Trigger) {
        lock.lock()
        defer { lock.unlock() }

        // Remove existing trigger with same ID
        triggers.removeAll { $0.id == trigger.id }
        triggers.append(trigger)
        saveTriggers()
    }

    /// Remove a trigger
    func removeTrigger(id: String) {
        lock.lock()
        defer { lock.unlock() }

        triggers.removeAll { $0.id == id }
        saveTriggers()
    }

    /// Get all triggers
    func getAllTriggers() -> [Trigger] {
        lock.lock()
        defer { lock.unlock() }
        return triggers
    }

    // MARK: - Utilities

    /// Haversine distance in meters between two coordinates
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0  // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }
}
