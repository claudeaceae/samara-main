import XCTest

final class LocationTrackerTests: SamaraTestCase {

    private struct TrackerPaths {
        let baseDir: URL
        let historyPath: URL
        let knownPlacesPath: URL
        let placesPath: URL
        let subwayPath: URL
        let patternsPath: URL
        let statePath: URL
    }

    private func makePaths() throws -> TrackerPaths {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-location-tracker-\(UUID().uuidString)")
        let stateDir = baseDir.appendingPathComponent("state")
        let memoryDir = baseDir.appendingPathComponent("memory")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)

        return TrackerPaths(
            baseDir: baseDir,
            historyPath: stateDir.appendingPathComponent("location-history.jsonl"),
            knownPlacesPath: memoryDir.appendingPathComponent("known-places.json"),
            placesPath: stateDir.appendingPathComponent("places.json"),
            subwayPath: stateDir.appendingPathComponent("subway-stations.json"),
            patternsPath: stateDir.appendingPathComponent("location-patterns.json"),
            statePath: stateDir.appendingPathComponent("location-tracker-state.json")
        )
    }

    private func writePlaces(_ places: [LocationTracker.Place], to url: URL) throws {
        let file = LocationTracker.PlacesFile(places: places)
        let data = try JSONEncoder().encode(file)
        try data.write(to: url)
    }

    private func writeSubwayStations(_ stations: [LocationTracker.SubwayStation], to url: URL) throws {
        let file = LocationTracker.SubwayFile(stations: stations)
        let data = try JSONEncoder().encode(file)
        try data.write(to: url)
    }

    private func writeKnownPlaces(_ places: [String: LocationTracker.LocationEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(places)
        try data.write(to: url)
    }

    private func writeTrackerState(wasAtHome: Bool, wasAtWork: Bool?, to url: URL) throws {
        var fields: [String: Any] = ["wasAtHome": wasAtHome]
        if let wasAtWork = wasAtWork {
            fields["wasAtWork"] = wasAtWork
        }
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted])
        try data.write(to: url)
    }

    private func writeHistory(_ entries: [LocationTracker.LocationEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var lines: [String] = []
        for entry in entries {
            let data = try encoder.encode(entry)
            lines.append(String(data: data, encoding: .utf8)!)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeUpdate(lat: Double, lon: Double, timestamp: Date = Date(), speed: Double? = nil, wifi: String? = nil, motion: [String] = []) -> LocationUpdate {
        LocationUpdate(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: nil,
            speed: speed,
            battery: nil,
            wifi: wifi,
            motion: motion
        )
    }

    func testProcessLocationTriggersLeavingHome() throws {
        let paths = try makePaths()
        // Home radius 5000m, so position at 40.002 is only ~220m away - need to be outside radius + 50m
        let home = LocationTracker.Place(name: "home", label: "Home Base", lat: 40.0, lon: -73.0, radiusM: 100, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: true, wasAtWork: false, to: paths.statePath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // Need 3 consecutive away readings with movement to trigger (hysteresis + motion check)
        // Position at 40.002 is ~220m from home, outside 100m + 50m = 150m threshold
        let awayUpdate = makeUpdate(lat: 40.002, lon: -73.0, speed: 2.0, motion: ["walking"])

        // First 2 readings accumulate hysteresis counter but don't trigger
        let analysis1 = tracker.processLocation(awayUpdate)
        XCTAssertFalse(analysis1.shouldMessage, "First away reading should not trigger")

        let analysis2 = tracker.processLocation(awayUpdate)
        XCTAssertFalse(analysis2.shouldMessage, "Second away reading should not trigger")

        // Third reading triggers the departure
        let analysis3 = tracker.processLocation(awayUpdate)
        XCTAssertTrue(analysis3.shouldMessage, "Third away reading should trigger")
        XCTAssertEqual(analysis3.triggerType, .leavingHome)

        // Verify triggerContext is populated alongside reason
        XCTAssertNotNil(analysis3.triggerContext)
        XCTAssertEqual(analysis3.triggerContext?.triggerType, .leavingHome)
        XCTAssertEqual(analysis3.triggerContext?.placeName, "home")
        XCTAssertNotNil(analysis3.reason, "Fallback reason should still be present")
    }

    func testProcessLocationTriggersNearTransit() throws {
        let paths = try makePaths()
        let place = LocationTracker.Place(name: "office", label: "Office", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil, wifiHints: nil)
        try writePlaces([place], to: paths.placesPath)

        let station = LocationTracker.SubwayStation(name: "Test Station", lat: 40.0, lon: -73.0, stopId: nil)
        try writeSubwayStations([station], to: paths.subwayPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        let update = makeUpdate(lat: 40.0, lon: -73.0)
        let analysis = tracker.processLocation(update)

        XCTAssertTrue(analysis.shouldMessage)
        XCTAssertEqual(analysis.triggerType, .nearTransit)
        XCTAssertTrue(analysis.reason?.contains("Near Test Station") == true)

        // Verify triggerContext is populated with station name
        XCTAssertNotNil(analysis.triggerContext)
        XCTAssertEqual(analysis.triggerContext?.triggerType, .nearTransit)
        XCTAssertEqual(analysis.triggerContext?.placeName, "Test Station")
        XCTAssertNotNil(analysis.reason, "Fallback reason should still be present")
    }

    func testGetPatternSummaryIncludesKnownPlaces() throws {
        let paths = try makePaths()
        let homeEntry = LocationTracker.LocationEntry(
            timestamp: Date(),
            latitude: 40.0,
            longitude: -73.0,
            address: "Home",
            altitude: nil,
            speed: nil,
            motion: [],
            wifi: nil
        )
        try writeKnownPlaces(["Home": homeEntry], to: paths.knownPlacesPath)

        let place = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil, wifiHints: nil)
        try writePlaces([place], to: paths.placesPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        _ = tracker.processLocation(makeUpdate(lat: 40.0, lon: -73.0))

        let summary = tracker.getPatternSummary()
        XCTAssertTrue(summary.contains("Recent locations: 1 entries"))
        XCTAssertTrue(summary.contains("Known places: Home"))
    }

    func testCurrentPlaceNameUsesLabel() throws {
        let paths = try makePaths()
        let place = LocationTracker.Place(name: "office", label: "HQ", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil, wifiHints: nil)
        try writePlaces([place], to: paths.placesPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        let entry = LocationTracker.LocationEntry(
            timestamp: Date(),
            latitude: 40.0,
            longitude: -73.0,
            address: "HQ",
            altitude: nil,
            speed: nil,
            motion: [],
            wifi: nil
        )

        XCTAssertEqual(tracker.currentPlaceName(for: entry), "HQ")
    }

    // MARK: - WiFi-First Place Matching Tests

    func testIsAtKnownPlaceUsesWiFiMatch() throws {
        let paths = try makePaths()
        // Home with 100m GPS radius and WiFi hint
        let home = LocationTracker.Place(name: "home", label: "É's apartment", lat: 40.67217, lon: -73.95, radiusM: 100, type: nil, wifiHints: ["cute aggression"])
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: true, wasAtWork: false, to: paths.statePath)

        // Seed history at home so isNewLocation doesn't fire
        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.67217, longitude: -73.95,
            address: "É's apartment", altitude: nil, speed: nil, motion: [], wifi: "cute aggression"
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // GPS drifts ~148m from home center (outside 100m radius), but WiFi matches
        let update = makeUpdate(lat: 40.6735, lon: -73.95, wifi: "cute aggression")
        let analysis = tracker.processLocation(update)

        // WiFi match proves we're home — no lingering/new-spot alerts
        XCTAssertFalse(analysis.shouldMessage, "WiFi match should suppress false alerts when GPS drifts at home")
    }

    func testAddressResolvesToPlaceLabelWithWiFi() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "É's apartment", lat: 40.67217, lon: -73.95, radiusM: 100, type: nil, wifiHints: ["cute aggression"])
        try writePlaces([home], to: paths.placesPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // GPS outside 100m radius but WiFi matches home
        let update = makeUpdate(lat: 40.6735, lon: -73.95, wifi: "cute aggression")
        let analysis = tracker.processLocation(update)

        // Address should be place label, not "near cute aggression"
        XCTAssertEqual(analysis.currentLocation?.address, "É's apartment")
    }

    func testCurrentPlaceNameUsesWiFi() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "É's apartment", lat: 40.67217, lon: -73.95, radiusM: 100, type: nil, wifiHints: ["cute aggression"])
        try writePlaces([home], to: paths.placesPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // GPS outside radius but WiFi matches
        let entry = LocationTracker.LocationEntry(
            timestamp: Date(),
            latitude: 40.6735, longitude: -73.95,
            address: "near cute aggression", altitude: nil, speed: nil, motion: [],
            wifi: "cute aggression"
        )

        XCTAssertEqual(tracker.currentPlaceName(for: entry), "É's apartment")
    }

    func testArrivingHomeDetectedByWiFi() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "É's apartment", lat: 40.67217, lon: -73.95, radiusM: 100, type: nil, wifiHints: ["cute aggression"])
        try writePlaces([home], to: paths.placesPath)
        // Start as away from home
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        // Seed history so isNewLocation doesn't fire
        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.67217, longitude: -73.95,
            address: "É's apartment", altitude: nil, speed: nil, motion: [], wifi: "cute aggression"
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // GPS outside radius but WiFi matches home — should detect arrival
        let update = makeUpdate(lat: 40.6735, lon: -73.95, wifi: "cute aggression")
        let analysis = tracker.processLocation(update)

        XCTAssertTrue(analysis.shouldMessage, "WiFi match should trigger arriving home even with GPS outside radius")
        XCTAssertEqual(analysis.triggerType, .arrivingHome)

        // Verify triggerContext is populated for arrival
        XCTAssertNotNil(analysis.triggerContext)
        XCTAssertEqual(analysis.triggerContext?.triggerType, .arrivingHome)
        XCTAssertEqual(analysis.triggerContext?.placeName, "home")
        XCTAssertEqual(analysis.triggerContext?.arrivalConfidence, "wifi_confirmed")
        XCTAssertNotNil(analysis.reason, "Fallback reason should still be present")
    }

    // MARK: - TriggerContext Tests

    func testTriggerContextIncludesTimeOfDay() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 100, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        // Seed history so isNewLocation doesn't fire
        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // GPS-only arrival now requires 2 readings (hysteresis)
        let update = makeUpdate(lat: 40.0, lon: -73.0)
        let analysis1 = tracker.processLocation(update)
        XCTAssertFalse(analysis1.shouldMessage, "First GPS reading should not trigger arrival")

        let analysis2 = tracker.processLocation(update)
        XCTAssertTrue(analysis2.shouldMessage, "Second GPS reading should trigger arrival")
        XCTAssertNotNil(analysis2.triggerContext)
        let timeOfDay = analysis2.triggerContext!.timeOfDay
        XCTAssertTrue(["morning", "afternoon", "evening", "night"].contains(timeOfDay),
                       "timeOfDay should be one of the expected values, got: \(timeOfDay)")
    }

    func testNonTriggeringAnalysisHasNilContext() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: true, wasAtWork: false, to: paths.statePath)

        // Seed history so isNewLocation doesn't fire
        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // At home, already wasAtHome — no trigger
        let update = makeUpdate(lat: 40.0, lon: -73.0)
        let analysis = tracker.processLocation(update)

        XCTAssertFalse(analysis.shouldMessage)
        XCTAssertNil(analysis.triggerContext, "Non-triggering analysis should have nil triggerContext")
    }

    // MARK: - Arrival Hysteresis Tests

    func testArrivingHomeRequiresMultipleReadings() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 150, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        // Seed history so isNewLocation doesn't fire
        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // Stationary within radius (no speed, no motion)
        let homeUpdate = makeUpdate(lat: 40.0, lon: -73.0)

        // First reading: no trigger (hysteresis counter at 1/2)
        let analysis1 = tracker.processLocation(homeUpdate)
        XCTAssertFalse(analysis1.shouldMessage, "First GPS reading should not trigger arrival")

        // Second reading: trigger (hysteresis counter at 2/2)
        let analysis2 = tracker.processLocation(homeUpdate)
        XCTAssertTrue(analysis2.shouldMessage, "Second GPS reading should trigger arrival")
        XCTAssertEqual(analysis2.triggerType, .arrivingHome)
        XCTAssertEqual(analysis2.triggerContext?.arrivalConfidence, "gps_hysteresis")
    }

    func testArrivingHomeSuppressedWhileMoving() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 150, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // 5 readings while driving through home radius — none should trigger
        let drivingUpdate = makeUpdate(lat: 40.0, lon: -73.0, speed: 10.0, motion: ["automotive"])
        for i in 1...5 {
            let analysis = tracker.processLocation(drivingUpdate)
            XCTAssertFalse(analysis.shouldMessage, "Reading \(i) while driving should not trigger arrival")
        }

        // Stop moving, then 2 stationary readings should trigger
        let stoppedUpdate = makeUpdate(lat: 40.0, lon: -73.0, speed: 0.0, motion: ["stationary"])
        let analysis1 = tracker.processLocation(stoppedUpdate)
        XCTAssertFalse(analysis1.shouldMessage, "First stationary reading should not trigger (hysteresis)")

        let analysis2 = tracker.processLocation(stoppedUpdate)
        XCTAssertTrue(analysis2.shouldMessage, "Second stationary reading should trigger arrival")
        XCTAssertEqual(analysis2.triggerType, .arrivingHome)
    }

    func testArrivingHomeWiFiBypassesHysteresis() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 150, type: nil, wifiHints: ["HomeWiFi"])
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // WiFi match should trigger on first reading, even with movement
        let wifiUpdate = makeUpdate(lat: 40.0, lon: -73.0, speed: 5.0, wifi: "HomeWiFi", motion: ["walking"])
        let analysis = tracker.processLocation(wifiUpdate)

        XCTAssertTrue(analysis.shouldMessage, "WiFi match should trigger immediately, bypassing hysteresis")
        XCTAssertEqual(analysis.triggerType, .arrivingHome)
        XCTAssertEqual(analysis.triggerContext?.arrivalConfidence, "wifi_confirmed")
    }

    func testLeavingWorkRequiresMultipleReadings() throws {
        let paths = try makePaths()
        let work = LocationTracker.Place(name: "work", label: "Office", lat: 40.0, lon: -73.0, radiusM: 100, type: nil, wifiHints: nil)
        try writePlaces([work], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: true, to: paths.statePath)

        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Office", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // Away from work with movement (~220m from center, beyond 100+50=150m threshold)
        let awayUpdate = makeUpdate(lat: 40.002, lon: -73.0, speed: 2.0, motion: ["walking"])

        // First 2 readings accumulate hysteresis but don't trigger
        let analysis1 = tracker.processLocation(awayUpdate)
        XCTAssertFalse(analysis1.shouldMessage, "First away reading should not trigger work departure")

        let analysis2 = tracker.processLocation(awayUpdate)
        XCTAssertFalse(analysis2.shouldMessage, "Second away reading should not trigger work departure")

        // Third reading triggers (3-reading hysteresis)
        let analysis3 = tracker.processLocation(awayUpdate)
        XCTAssertTrue(analysis3.shouldMessage, "Third away reading should trigger work departure")
        XCTAssertEqual(analysis3.triggerType, .leavingWork)
    }

    func testTriggerContextIncludesDistanceAndConfidence() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 150, type: nil, wifiHints: nil)
        try writePlaces([home], to: paths.placesPath)
        try writeTrackerState(wasAtHome: false, wasAtWork: false, to: paths.statePath)

        let historyEntry = LocationTracker.LocationEntry(
            timestamp: Date(timeIntervalSinceNow: -300),
            latitude: 40.0, longitude: -73.0,
            address: "Home", altitude: nil, speed: nil, motion: [], wifi: nil
        )
        try writeHistory([historyEntry], to: paths.historyPath)

        let tracker = LocationTracker(
            historyPath: paths.historyPath.path,
            knownPlacesPath: paths.knownPlacesPath.path,
            placesPath: paths.placesPath.path,
            subwayPath: paths.subwayPath.path,
            patternsPath: paths.patternsPath.path,
            statePath: paths.statePath.path
        )

        // Send 2 readings to trigger arrival (hysteresis)
        let homeUpdate = makeUpdate(lat: 40.0001, lon: -73.0001)
        _ = tracker.processLocation(homeUpdate)
        let analysis = tracker.processLocation(homeUpdate)

        XCTAssertTrue(analysis.shouldMessage)
        XCTAssertEqual(analysis.triggerType, .arrivingHome)

        let ctx = analysis.triggerContext!
        XCTAssertNotNil(ctx.distanceFromPlaceM, "Should include distance from place")
        XCTAssertNotNil(ctx.latitude, "Should include latitude")
        XCTAssertNotNil(ctx.longitude, "Should include longitude")
        XCTAssertEqual(ctx.arrivalConfidence, "gps_hysteresis")
        XCTAssertEqual(ctx.latitude!, 40.0001, accuracy: 0.0001)
        XCTAssertEqual(ctx.longitude!, -73.0001, accuracy: 0.0001)
    }
}
