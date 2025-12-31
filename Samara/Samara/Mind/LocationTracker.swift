import Foundation

/// Tracks É's location over time and provides proactive awareness
final class LocationTracker {

    // MARK: - Types

    struct LocationEntry: Codable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let address: String
        let altitude: Double?

        /// Distance in meters to another location
        func distance(to other: LocationEntry) -> Double {
            let lat1 = latitude * .pi / 180
            let lat2 = other.latitude * .pi / 180
            let dLat = (other.latitude - latitude) * .pi / 180
            let dLon = (other.longitude - longitude) * .pi / 180

            let a = sin(dLat/2) * sin(dLat/2) +
                    cos(lat1) * cos(lat2) *
                    sin(dLon/2) * sin(dLon/2)
            let c = 2 * atan2(sqrt(a), sqrt(1-a))

            return 6371000 * c  // Earth radius in meters
        }
    }

    struct LocationAnalysis {
        let shouldMessage: Bool
        let reason: String?
        let currentLocation: LocationEntry?
    }

    // MARK: - Configuration

    private let historyPath: String
    private let knownPlacesPath: String

    /// Minimum time at same location before alerting (4 hours)
    private let stationaryAlertThreshold: TimeInterval = 4 * 60 * 60

    /// Distance threshold for "same location" (200 meters)
    private let sameLocationThreshold: Double = 200

    /// Distance threshold for "significant movement" (2 km)
    private let significantMovementThreshold: Double = 2000

    /// Minimum time between proactive messages (1 hour)
    private let messageCooldown: TimeInterval = 60 * 60

    // MARK: - State

    private var lastMessageTime: Date?
    private var lastKnownLocation: LocationEntry?
    private var locationHistory: [LocationEntry] = []
    private var knownPlaces: [String: LocationEntry] = [:]  // name -> location

    // MARK: - Initialization

    init(
        historyPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/memory/location-history.jsonl",
        knownPlacesPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/memory/known-places.json"
    ) {
        self.historyPath = historyPath
        self.knownPlacesPath = knownPlacesPath
        loadHistory()
        loadKnownPlaces()
    }

    // MARK: - Public Interface

    /// Process a location update from the note and determine if we should message
    func processLocationUpdate(noteContent: String) -> LocationAnalysis {
        guard let location = parseLocation(from: noteContent) else {
            print("[LocationTracker] Could not parse location from note")
            return LocationAnalysis(shouldMessage: false, reason: nil, currentLocation: nil)
        }

        // Store in history
        appendToHistory(location)

        // Check if we should message
        let analysis = analyzeLocation(location)

        // Update state
        lastKnownLocation = location

        return analysis
    }

    /// Get summary of location patterns (for context building)
    func getPatternSummary() -> String {
        guard !locationHistory.isEmpty else {
            return "No location history yet."
        }

        var summary = "Location patterns:\n"

        // Recent locations
        let recent = locationHistory.suffix(10)
        summary += "- Recent locations: \(recent.count) entries\n"

        // Known places
        if !knownPlaces.isEmpty {
            summary += "- Known places: \(knownPlaces.keys.joined(separator: ", "))\n"
        }

        // Time at current location
        if let current = lastKnownLocation {
            let duration = durationAtCurrentLocation(current)
            if duration > 60 * 60 {  // More than 1 hour
                let hours = Int(duration / 3600)
                summary += "- At current location for ~\(hours) hour(s)\n"
            }
        }

        return summary
    }

    // MARK: - Private Methods

    private func parseLocation(from noteContent: String) -> LocationEntry? {
        // Parse the location note format (entries separated by "—"):
        // It's 12/19/25, 13:00
        // Edouard is currently located here:
        // 777 Franklin Ave
        // New York NY 11238
        // United States
        // Altitude: 38.91201399736
        // Longitude, Latitude: 40.67215480358847,-73.95709702084842
        // —

        // Split by entry delimiter and get the LAST entry
        let entries = noteContent.components(separatedBy: "—")
        let lastEntry = entries.last { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.contains("Longitude")
        } ?? noteContent

        let lines = lastEntry.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var address = ""
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var timestamp = Date()

        for (index, line) in lines.enumerated() {
            // Parse timestamp
            if line.starts(with: "It's ") {
                // Could parse this, but use current time for simplicity
                timestamp = Date()
            }

            // Parse coordinates
            if line.starts(with: "Longitude, Latitude:") || line.contains(",") && line.contains(".") {
                let coordLine = line.replacingOccurrences(of: "Longitude, Latitude:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = coordLine.split(separator: ",")
                if parts.count == 2 {
                    latitude = Double(parts[0].trimmingCharacters(in: .whitespaces))
                    longitude = Double(parts[1].trimmingCharacters(in: .whitespaces))
                }
            }

            // Parse altitude
            if line.starts(with: "Altitude:") {
                let altStr = line.replacingOccurrences(of: "Altitude:", with: "").trimmingCharacters(in: .whitespaces)
                altitude = Double(altStr)
            }

            // Build address from location lines
            if line.starts(with: "Edouard is currently located here:") {
                // Next few lines are address
                var addressLines: [String] = []
                for i in (index + 1)..<min(index + 5, lines.count) {
                    let addrLine = lines[i]
                    if addrLine.isEmpty || addrLine.starts(with: "Altitude") || addrLine.starts(with: "Longitude") {
                        break
                    }
                    addressLines.append(addrLine)
                }
                address = addressLines.joined(separator: ", ")
            }
        }

        guard let lat = latitude, let lon = longitude else {
            return nil
        }

        return LocationEntry(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            address: address,
            altitude: altitude
        )
    }

    private func analyzeLocation(_ location: LocationEntry) -> LocationAnalysis {
        // Check cooldown
        if let lastMsg = lastMessageTime, Date().timeIntervalSince(lastMsg) < messageCooldown {
            return LocationAnalysis(shouldMessage: false, reason: "Cooldown active", currentLocation: location)
        }

        // Check 1: New location (never seen before)
        if isNewLocation(location) {
            lastMessageTime = Date()
            return LocationAnalysis(
                shouldMessage: true,
                reason: "You're somewhere new! \(location.address). Exploring?",
                currentLocation: location
            )
        }

        // Check 2: Significant movement since last update
        if let last = lastKnownLocation {
            let distance = location.distance(to: last)
            if distance > significantMovementThreshold {
                let km = distance / 1000
                lastMessageTime = Date()
                return LocationAnalysis(
                    shouldMessage: true,
                    reason: String(format: "Noticed you moved ~%.1f km. On the go?", km),
                    currentLocation: location
                )
            }
        }

        // Check 3: Stationary for a long time
        let duration = durationAtCurrentLocation(location)
        if duration > stationaryAlertThreshold {
            let hours = Int(duration / 3600)
            // Only alert once per stationary period
            if shouldAlertStationary(location, duration: duration) {
                lastMessageTime = Date()
                return LocationAnalysis(
                    shouldMessage: true,
                    reason: "You've been at \(simplifyAddress(location.address)) for \(hours)+ hours. Everything okay?",
                    currentLocation: location
                )
            }
        }

        // Check 4: Time-based anomalies (future enhancement)
        // Could check if location is unusual for current time of day

        return LocationAnalysis(shouldMessage: false, reason: nil, currentLocation: location)
    }

    private func isNewLocation(_ location: LocationEntry) -> Bool {
        // Check if we've ever been within threshold of this location
        for entry in locationHistory {
            if location.distance(to: entry) < sameLocationThreshold {
                return false
            }
        }
        return true
    }

    private func durationAtCurrentLocation(_ location: LocationEntry) -> TimeInterval {
        // Look back through history to find how long at this spot
        var duration: TimeInterval = 0
        let reversed = locationHistory.reversed()

        for entry in reversed {
            if location.distance(to: entry) < sameLocationThreshold {
                duration = location.timestamp.timeIntervalSince(entry.timestamp)
            } else {
                break
            }
        }

        return duration
    }

    private func shouldAlertStationary(_ location: LocationEntry, duration: TimeInterval) -> Bool {
        // Don't re-alert if we already messaged about this stationary period
        // Check if our last message was about being stationary at this location
        guard let lastMsg = lastMessageTime else { return true }

        // If last message was more than the threshold ago, alert again
        return Date().timeIntervalSince(lastMsg) > stationaryAlertThreshold
    }

    private func simplifyAddress(_ address: String) -> String {
        // Return just the main part of the address
        let parts = address.components(separatedBy: ",")
        if parts.count > 0 {
            return parts[0].trimmingCharacters(in: .whitespaces)
        }
        return address
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyPath) else { return }

        do {
            let content = try String(contentsOfFile: historyPath, encoding: .utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                if let data = line.data(using: .utf8),
                   let entry = try? decoder.decode(LocationEntry.self, from: data) {
                    locationHistory.append(entry)
                }
            }

            // Keep last 1000 entries
            if locationHistory.count > 1000 {
                locationHistory = Array(locationHistory.suffix(1000))
            }

            print("[LocationTracker] Loaded \(locationHistory.count) history entries")
        } catch {
            print("[LocationTracker] Error loading history: \(error)")
        }
    }

    private func appendToHistory(_ entry: LocationEntry) {
        locationHistory.append(entry)

        // Ensure directory exists
        let dir = (historyPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Append to file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(entry)
            if let jsonString = String(data: data, encoding: .utf8) {
                let line = jsonString + "\n"
                if let fileHandle = FileHandle(forWritingAtPath: historyPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(line.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try line.write(toFile: historyPath, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            print("[LocationTracker] Error saving history: \(error)")
        }
    }

    private func loadKnownPlaces() {
        guard FileManager.default.fileExists(atPath: knownPlacesPath) else { return }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: knownPlacesPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            knownPlaces = try decoder.decode([String: LocationEntry].self, from: data)
            print("[LocationTracker] Loaded \(knownPlaces.count) known places")
        } catch {
            print("[LocationTracker] Error loading known places: \(error)")
        }
    }

    func saveKnownPlace(name: String, location: LocationEntry) {
        knownPlaces[name] = location

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(knownPlaces)
            try data.write(to: URL(fileURLWithPath: knownPlacesPath))
            print("[LocationTracker] Saved known place: \(name)")
        } catch {
            print("[LocationTracker] Error saving known places: \(error)")
        }
    }
}
