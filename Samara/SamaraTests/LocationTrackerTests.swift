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

    private func makeUpdate(lat: Double, lon: Double, timestamp: Date = Date(), motion: [String] = []) -> LocationUpdate {
        LocationUpdate(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: nil,
            speed: nil,
            battery: nil,
            wifi: nil,
            motion: motion
        )
    }

    func testProcessLocationTriggersLeavingHome() throws {
        let paths = try makePaths()
        let home = LocationTracker.Place(name: "home", label: "Home Base", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil)
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

        let update = makeUpdate(lat: 40.002, lon: -73.0)
        let analysis = tracker.processLocation(update)

        XCTAssertTrue(analysis.shouldMessage)
        XCTAssertEqual(analysis.triggerType, .leavingHome)
    }

    func testProcessLocationTriggersNearTransit() throws {
        let paths = try makePaths()
        let place = LocationTracker.Place(name: "office", label: "Office", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil)
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
            motion: []
        )
        try writeKnownPlaces(["Home": homeEntry], to: paths.knownPlacesPath)

        let place = LocationTracker.Place(name: "home", label: "Home", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil)
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
        let place = LocationTracker.Place(name: "office", label: "HQ", lat: 40.0, lon: -73.0, radiusM: 5000, type: nil)
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
            motion: []
        )

        XCTAssertEqual(tracker.currentPlaceName(for: entry), "HQ")
    }
}
