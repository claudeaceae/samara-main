import Foundation

/// Tracks É's location over time and provides proactive awareness
final class LocationTracker {

    // MARK: - Types

    enum TriggerType: String {
        case newLocation = "new_location"
        case significantMovement = "significant_movement"
        case stationary = "stationary"
        case leavingHome = "leaving_home"
        case arrivingHome = "arriving_home"
        case leavingWork = "leaving_work"
        case arrivingWork = "arriving_work"
        case nearTransit = "near_transit"
        case lingering = "lingering"
        case patternDeviation = "pattern_deviation"
    }

    struct LocationEntry: Codable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let address: String
        let altitude: Double?

        /// Distance in meters to another location
        func distance(to other: LocationEntry) -> Double {
            return LocationTracker.haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: other.latitude, lon2: other.longitude
            )
        }

        /// Distance in meters to a coordinate pair
        func distance(toLat lat: Double, lon: Double) -> Double {
            return LocationTracker.haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: lat, lon2: lon
            )
        }
    }

    struct LocationAnalysis {
        let shouldMessage: Bool
        let reason: String?
        let currentLocation: LocationEntry?
        let triggerType: TriggerType?
    }

    /// Place definition from places.json
    struct Place: Codable {
        let name: String
        let label: String?
        let lat: Double
        let lon: Double
        let radiusM: Double?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case name, label, lat, lon, type
            case radiusM = "radius_m"
        }

        var radius: Double { radiusM ?? 100 }
    }

    struct PlacesFile: Codable {
        let places: [Place]
    }

    /// Subway station from subway-stations.json
    struct SubwayStation: Codable {
        let name: String
        let lat: Double
        let lon: Double
        let stopId: String?

        enum CodingKeys: String, CodingKey {
            case name, lat, lon
            case stopId = "stop_id"
        }
    }

    struct SubwayFile: Codable {
        let stations: [SubwayStation]
    }

    /// Location patterns from learn-location-patterns
    struct TimePattern: Codable {
        let typicalTime: String?
        let stdDevM: Int?
        let sampleSize: Int?

        enum CodingKeys: String, CodingKey {
            case typicalTime = "typical_time"
            case stdDevM = "std_dev_m"
            case sampleSize = "sample_size"
        }

        /// Parse typical time as hours since midnight
        var typicalHour: Double? {
            guard let time = typicalTime else { return nil }
            let parts = time.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { return nil }
            return Double(hour) + Double(minute) / 60.0
        }
    }

    struct DepartureReturnPattern: Codable {
        let weekday: TimePattern?
        let weekend: TimePattern?
    }

    struct LocationPatterns: Codable {
        let updated: String?
        let homeDeparture: DepartureReturnPattern?
        let homeReturn: DepartureReturnPattern?

        enum CodingKeys: String, CodingKey {
            case updated
            case homeDeparture = "home_departure"
            case homeReturn = "home_return"
        }
    }

    /// Haversine distance calculation
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0  // Earth radius in meters
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi/2) * sin(dPhi/2) +
                cos(phi1) * cos(phi2) *
                sin(dLambda/2) * sin(dLambda/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }

    // MARK: - Configuration

    private let historyPath: String
    private let knownPlacesPath: String
    private let placesPath: String
    private let subwayPath: String
    private let patternsPath: String
    private let statePath: String

    /// Minimum time at same location before alerting (4 hours)
    private let stationaryAlertThreshold: TimeInterval = 4 * 60 * 60

    /// Distance threshold for "same location" (200 meters)
    private let sameLocationThreshold: Double = 200

    /// Distance threshold for "significant movement" (2 km)
    private let significantMovementThreshold: Double = 2000

    /// Distance threshold for detecting home departure (75 meters - about 1 short NYC block)
    private let homeDepartureThreshold: Double = 75

    /// Distance threshold for transit proximity (100 meters)
    private let transitProximityThreshold: Double = 100

    /// Time threshold for lingering at unknown location (30 minutes)
    private let lingeringThreshold: TimeInterval = 30 * 60

    /// Minimum time between proactive messages (1 hour)
    private let messageCooldown: TimeInterval = 60 * 60

    // MARK: - State

    private var lastMessageTime: Date?
    private var lastKnownLocation: LocationEntry?
    private var locationHistory: [LocationEntry] = []
    private var knownPlaces: [String: LocationEntry] = [:]  // name -> location (legacy)
    private var places: [Place] = []  // from places.json
    private var subwayStations: [SubwayStation] = []
    private var patterns: LocationPatterns?  // learned patterns
    private var wasAtHome: Bool = false  // for detecting departure from home
    private var wasAtWork: Bool = false  // for detecting departure from work
    private var lastTransitAlert: String?  // prevent re-alerting same station
    private var lastPatternDeviationAlert: Date?  // prevent repeated deviation alerts

    // MARK: - Initialization

    init(
        historyPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/state/location-history.jsonl",
        knownPlacesPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/memory/known-places.json",
        placesPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/state/places.json",
        subwayPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/state/subway-stations.json",
        patternsPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/state/location-patterns.json",
        statePath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude-mind/state/location-tracker-state.json"
    ) {
        self.historyPath = historyPath
        self.knownPlacesPath = knownPlacesPath
        self.placesPath = placesPath
        self.subwayPath = subwayPath
        self.patternsPath = patternsPath
        self.statePath = statePath
        loadHistory()
        loadKnownPlaces()
        loadPlaces()
        loadSubwayStations()
        loadPatterns()
        loadTrackerState()

        // Initialize home state from last known location if not loaded from state
        if let home = findPlace(named: "home"), let last = locationHistory.last {
            let isCurrentlyHome = last.distance(toLat: home.lat, lon: home.lon) < home.radius
            // Only override if state wasn't loaded (wasAtHome defaults to false)
            if !wasAtHome && isCurrentlyHome {
                wasAtHome = isCurrentlyHome
                log("Initialized wasAtHome=\(wasAtHome) from last location", level: .debug, component: "LocationTracker")
            }
        }

        // Initialize work state from last known location if not loaded from state
        if let work = findPlace(named: "work"), let last = locationHistory.last {
            let isCurrentlyAtWork = last.distance(toLat: work.lat, lon: work.lon) < work.radius
            // Only override if state wasn't loaded (wasAtWork defaults to false)
            if !wasAtWork && isCurrentlyAtWork {
                wasAtWork = isCurrentlyAtWork
                log("Initialized wasAtWork=\(wasAtWork) from last location", level: .debug, component: "LocationTracker")
            }
        }
    }

    // MARK: - Public Interface

    /// Process a location update from the file watcher (primary method)
    func processLocation(_ update: LocationUpdate) -> LocationAnalysis {
        // Convert LocationUpdate to LocationEntry
        let location = LocationEntry(
            timestamp: update.timestamp,
            latitude: update.latitude,
            longitude: update.longitude,
            address: update.wifi ?? "Unknown",  // Use WiFi name as a proxy for location context
            altitude: update.altitude
        )

        // Store in history
        appendToHistory(location)

        // Check if we should message
        let analysis = analyzeLocation(location)

        // Update state
        lastKnownLocation = location

        return analysis
    }

    /// Process a location update from the note (DEPRECATED - use processLocation instead)
    @available(*, deprecated, message: "Use processLocation(_:) with LocationUpdate instead")
    func processLocationUpdate(noteContent: String) -> LocationAnalysis {
        guard let location = parseLocation(from: noteContent) else {
            log("Could not parse location from note", level: .debug, component: "LocationTracker")
            return LocationAnalysis(shouldMessage: false, reason: nil, currentLocation: nil, triggerType: nil)
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
            return LocationAnalysis(shouldMessage: false, reason: "Cooldown active", currentLocation: location, triggerType: nil)
        }

        // Check 1: Leaving home
        if let result = checkLeavingHome(location) {
            return result
        }

        // Check 1.5: Arriving home
        if let result = checkArrivingHome(location) {
            return result
        }

        // Check 1.6: Leaving work
        if let result = checkLeavingWork(location) {
            return result
        }

        // Check 1.7: Arriving at work
        if let result = checkArrivingWork(location) {
            return result
        }

        // Check 2: Near transit (subway station)
        if let result = checkNearTransit(location) {
            return result
        }

        // Check 3: Lingering at unknown location
        if let result = checkLingering(location) {
            return result
        }

        // Check 4: Pattern deviation (late departure, etc.)
        if let result = checkPatternDeviation(location) {
            return result
        }

        // Check 5: New location (never seen before)
        if isNewLocation(location) {
            lastMessageTime = Date()
            return LocationAnalysis(
                shouldMessage: true,
                reason: "You're somewhere new! \(location.address). Exploring?",
                currentLocation: location,
                triggerType: .newLocation
            )
        }

        // Check 6: Significant movement since last update
        if let last = lastKnownLocation {
            let distance = location.distance(to: last)
            if distance > significantMovementThreshold {
                let km = distance / 1000
                lastMessageTime = Date()
                return LocationAnalysis(
                    shouldMessage: true,
                    reason: String(format: "Noticed you moved ~%.1f km. On the go?", km),
                    currentLocation: location,
                    triggerType: .significantMovement
                )
            }
        }

        // Check 7: Stationary for a long time (but NOT at known places like home)
        // Being at home for extended periods is normal - don't alert about it
        if !isAtKnownPlace(location) {
            let duration = durationAtCurrentLocation(location)
            if duration > stationaryAlertThreshold {
                let hours = Int(duration / 3600)
                // Only alert once per stationary period
                if shouldAlertStationary(location, duration: duration) {
                    lastMessageTime = Date()
                    return LocationAnalysis(
                        shouldMessage: true,
                        reason: "You've been at \(simplifyAddress(location.address)) for \(hours)+ hours. Everything okay?",
                        currentLocation: location,
                        triggerType: .stationary
                    )
                }
            }
        }

        return LocationAnalysis(shouldMessage: false, reason: nil, currentLocation: location, triggerType: nil)
    }

    // MARK: - New Trigger Detection

    /// Check if leaving home
    private func checkLeavingHome(_ location: LocationEntry) -> LocationAnalysis? {
        guard let home = findPlace(named: "home") else { return nil }

        let distanceFromHome = location.distance(toLat: home.lat, lon: home.lon)
        let isNowAway = distanceFromHome > homeDepartureThreshold

        // Trigger: was at home, now away
        if wasAtHome && isNowAway {
            wasAtHome = false
            saveTrackerState()
            lastMessageTime = Date()
            log("Leaving home detected - wasAtHome=\(wasAtHome)", level: .info, component: "LocationTracker")
            return LocationAnalysis(
                shouldMessage: true,
                reason: "Heading out?",
                currentLocation: location,
                triggerType: .leavingHome
            )
        }

        // Update home state (but don't trigger here - let checkArrivingHome handle arrival)
        // Only update to false when leaving; arrival update happens in checkArrivingHome
        if isNowAway {
            wasAtHome = false
        }

        return nil
    }

    /// Check if arriving home
    private func checkArrivingHome(_ location: LocationEntry) -> LocationAnalysis? {
        guard let home = findPlace(named: "home") else { return nil }

        let distanceFromHome = location.distance(toLat: home.lat, lon: home.lon)
        let isNowHome = distanceFromHome < home.radius

        // Trigger: was away, now home
        if !wasAtHome && isNowHome {
            wasAtHome = true
            saveTrackerState()
            lastMessageTime = Date()
            log("Arriving home detected - wasAtHome=\(wasAtHome)", level: .info, component: "LocationTracker")
            return LocationAnalysis(
                shouldMessage: true,
                reason: "Welcome back!",
                currentLocation: location,
                triggerType: .arrivingHome
            )
        }

        return nil
    }

    /// Check if leaving work
    private func checkLeavingWork(_ location: LocationEntry) -> LocationAnalysis? {
        guard let work = findPlace(named: "work") else { return nil }

        let distanceFromWork = location.distance(toLat: work.lat, lon: work.lon)
        let isNowAway = distanceFromWork > homeDepartureThreshold  // reuse same threshold

        // Trigger: was at work, now away
        if wasAtWork && isNowAway {
            wasAtWork = false
            saveTrackerState()
            lastMessageTime = Date()
            log("Leaving work detected - wasAtWork=\(wasAtWork)", level: .info, component: "LocationTracker")
            return LocationAnalysis(
                shouldMessage: true,
                reason: "Heading home?",
                currentLocation: location,
                triggerType: .leavingWork
            )
        }

        // Update work state when leaving
        if isNowAway {
            wasAtWork = false
        }

        return nil
    }

    /// Check if arriving at work
    private func checkArrivingWork(_ location: LocationEntry) -> LocationAnalysis? {
        guard let work = findPlace(named: "work") else { return nil }

        let distanceFromWork = location.distance(toLat: work.lat, lon: work.lon)
        let isNowAtWork = distanceFromWork < work.radius

        // Trigger: was away, now at work
        if !wasAtWork && isNowAtWork {
            wasAtWork = true
            saveTrackerState()
            lastMessageTime = Date()
            log("Arriving at work detected - wasAtWork=\(wasAtWork)", level: .info, component: "LocationTracker")
            return LocationAnalysis(
                shouldMessage: true,
                reason: "Made it to work!",
                currentLocation: location,
                triggerType: .arrivingWork
            )
        }

        return nil
    }

    /// Check if near a subway station
    private func checkNearTransit(_ location: LocationEntry) -> LocationAnalysis? {
        guard !subwayStations.isEmpty else { return nil }

        for station in subwayStations {
            let distance = location.distance(toLat: station.lat, lon: station.lon)
            if distance < transitProximityThreshold {
                // Don't re-alert for same station
                if lastTransitAlert == station.name { return nil }

                lastTransitAlert = station.name
                lastMessageTime = Date()
                return LocationAnalysis(
                    shouldMessage: true,
                    reason: "Near \(station.name) — taking the train?",
                    currentLocation: location,
                    triggerType: .nearTransit
                )
            }
        }

        // Clear transit alert when not near any station
        lastTransitAlert = nil
        return nil
    }

    /// Check if lingering at an unknown location
    private func checkLingering(_ location: LocationEntry) -> LocationAnalysis? {
        // Only check if we're not at a known place
        if isAtKnownPlace(location) { return nil }

        let duration = durationAtCurrentLocation(location)
        if duration > lingeringThreshold {
            // Only alert once per lingering period (use stationary logic)
            if shouldAlertStationary(location, duration: duration) {
                let minutes = Int(duration / 60)
                lastMessageTime = Date()
                return LocationAnalysis(
                    shouldMessage: true,
                    reason: "You've been at \(simplifyAddress(location.address)) for \(minutes) minutes. Found a new spot?",
                    currentLocation: location,
                    triggerType: .lingering
                )
            }
        }
        return nil
    }

    /// Find a named place
    private func findPlace(named name: String) -> Place? {
        return places.first { $0.name == name }
    }

    /// Check if location is at any known place
    private func isAtKnownPlace(_ location: LocationEntry) -> Bool {
        if places.isEmpty {
            log("isAtKnownPlace: No places loaded!", level: .warn, component: "LocationTracker")
            return false
        }

        for place in places {
            let distance = location.distance(toLat: place.lat, lon: place.lon)
            if distance < place.radius {
                log("isAtKnownPlace: At \(place.name) (distance: \(Int(distance))m, radius: \(Int(place.radius))m)", level: .debug, component: "LocationTracker")
                return true
            }
        }

        // Log distances to all places for debugging
        let placeSummary = places.map { "\($0.name): \(Int(location.distance(toLat: $0.lat, lon: $0.lon)))m" }.joined(separator: ", ")
        log("isAtKnownPlace: Not at any known place. Distances: \(placeSummary)", level: .debug, component: "LocationTracker")
        return false
    }

    /// Get name of current place, if at one
    func currentPlaceName(for location: LocationEntry) -> String? {
        for place in places {
            if location.distance(toLat: place.lat, lon: place.lon) < place.radius {
                return place.label ?? place.name
            }
        }
        return nil
    }

    /// Check for pattern deviations (e.g., late departure from home)
    private func checkPatternDeviation(_ location: LocationEntry) -> LocationAnalysis? {
        guard let patterns = patterns,
              let home = findPlace(named: "home") else { return nil }

        // Only check once per 4 hours to avoid repeated alerts
        if let lastAlert = lastPatternDeviationAlert,
           Date().timeIntervalSince(lastAlert) < 4 * 60 * 60 {
            return nil
        }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentHour = Double(hour) + Double(minute) / 60.0
        let isWeekday = calendar.component(.weekday, from: now) >= 2 &&
                        calendar.component(.weekday, from: now) <= 6

        let atHome = location.distance(toLat: home.lat, lon: home.lon) < home.radius

        // Check: Still at home past typical departure time?
        if atHome {
            let departurePattern = isWeekday ?
                patterns.homeDeparture?.weekday :
                patterns.homeDeparture?.weekend

            if let typicalHour = departurePattern?.typicalHour,
               let stdDev = departurePattern?.stdDevM {
                // Alert if more than 2 std devs late (roughly 2 hours for typical pattern)
                let lateThreshold = typicalHour + (Double(stdDev) * 2 / 60.0)
                if currentHour > lateThreshold && currentHour < 14 {  // Only before 2pm
                    lastPatternDeviationAlert = Date()
                    lastMessageTime = Date()

                    let typicalTime = departurePattern?.typicalTime ?? "your usual time"
                    return LocationAnalysis(
                        shouldMessage: true,
                        reason: "Still home? You usually head out around \(typicalTime).",
                        currentLocation: location,
                        triggerType: .patternDeviation
                    )
                }
            }
        }

        // Could add more pattern checks here:
        // - Late return home
        // - Unusual location for time of day
        // - Missing regular visits to frequent places

        return nil
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
        // Find when we arrived at current location by looking for the most recent "away" entry
        // Then calculate time from arrival to now
        guard !locationHistory.isEmpty else { return 0 }

        var lastAwayIndex: Int? = nil

        // Walk backward through history to find most recent entry NOT at current location
        for (index, entry) in locationHistory.enumerated().reversed() {
            if location.distance(to: entry) >= sameLocationThreshold {
                lastAwayIndex = index
                break
            }
        }

        // Determine arrival time:
        // - If we found an "away" entry, arrival is the entry AFTER it
        // - If we never left (no away entry), arrival is the first entry in history
        let arrivalIndex = (lastAwayIndex ?? -1) + 1
        guard arrivalIndex < locationHistory.count else { return 0 }

        let arrivalTime = locationHistory[arrivalIndex].timestamp
        let duration = Date().timeIntervalSince(arrivalTime)

        log("Duration calculation: arrivalIndex=\(arrivalIndex), arrivalTime=\(arrivalTime), duration=\(Int(duration/3600))h", level: .debug, component: "LocationTracker")

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

            log("Loaded \(locationHistory.count) history entries", level: .debug, component: "LocationTracker")
        } catch {
            log("Error loading history: \(error)", level: .warn, component: "LocationTracker")
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
            log("Error saving history: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    private func loadKnownPlaces() {
        guard FileManager.default.fileExists(atPath: knownPlacesPath) else { return }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: knownPlacesPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            knownPlaces = try decoder.decode([String: LocationEntry].self, from: data)
            log("Loaded \(knownPlaces.count) known places", level: .debug, component: "LocationTracker")
        } catch {
            log("Error loading known places: \(error)", level: .warn, component: "LocationTracker")
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
            log("Saved known place: \(name)", level: .debug, component: "LocationTracker")
        } catch {
            log("Error saving known places: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    private func loadPlaces() {
        guard FileManager.default.fileExists(atPath: placesPath) else {
            log("Places file not found at \(placesPath)", level: .warn, component: "LocationTracker")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: placesPath))
            let placesFile = try JSONDecoder().decode(PlacesFile.self, from: data)
            places = placesFile.places
            let placeNames = places.map { "\($0.name) at (\($0.lat), \($0.lon)) r=\(Int($0.radius))m" }.joined(separator: ", ")
            log("Loaded \(places.count) places: \(placeNames)", level: .info, component: "LocationTracker")
        } catch {
            log("Error loading places: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    private func loadSubwayStations() {
        guard FileManager.default.fileExists(atPath: subwayPath) else {
            log("Subway stations file not found at \(subwayPath)", level: .debug, component: "LocationTracker")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: subwayPath))
            let subwayFile = try JSONDecoder().decode(SubwayFile.self, from: data)
            subwayStations = subwayFile.stations
            log("Loaded \(subwayStations.count) subway stations", level: .debug, component: "LocationTracker")
        } catch {
            log("Error loading subway stations: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    private func loadPatterns() {
        guard FileManager.default.fileExists(atPath: patternsPath) else {
            log("Patterns file not found at \(patternsPath)", level: .debug, component: "LocationTracker")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: patternsPath))
            patterns = try JSONDecoder().decode(LocationPatterns.self, from: data)
            log("Loaded location patterns", level: .debug, component: "LocationTracker")
        } catch {
            log("Error loading patterns: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    // MARK: - Tracker State Persistence

    private struct TrackerState: Codable {
        var wasAtHome: Bool
        var wasAtWork: Bool?  // Optional for backwards compatibility
        var lastMessageTime: Date?
        var lastTransitAlert: String?
    }

    private func loadTrackerState() {
        guard FileManager.default.fileExists(atPath: statePath) else {
            log("Tracker state file not found at \(statePath) - using defaults", level: .debug, component: "LocationTracker")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(TrackerState.self, from: data)
            wasAtHome = state.wasAtHome
            wasAtWork = state.wasAtWork ?? false
            lastMessageTime = state.lastMessageTime
            lastTransitAlert = state.lastTransitAlert
            log("Loaded tracker state: wasAtHome=\(wasAtHome), wasAtWork=\(wasAtWork)", level: .debug, component: "LocationTracker")
        } catch {
            log("Error loading tracker state: \(error)", level: .warn, component: "LocationTracker")
        }
    }

    private func saveTrackerState() {
        let state = TrackerState(
            wasAtHome: wasAtHome,
            wasAtWork: wasAtWork,
            lastMessageTime: lastMessageTime,
            lastTransitAlert: lastTransitAlert
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: statePath))
            log("Saved tracker state: wasAtHome=\(wasAtHome), wasAtWork=\(wasAtWork)", level: .debug, component: "LocationTracker")
        } catch {
            log("Error saving tracker state: \(error)", level: .warn, component: "LocationTracker")
        }
    }
}
