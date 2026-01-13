import Foundation

/// Represents a location update from the location.json file
struct LocationUpdate {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let speed: Double?
    let battery: Double?
    let wifi: String?
    let motion: [String]
}

/// Watches ~/.claude-mind/state/location.json for changes and triggers callbacks
final class LocationFileWatcher {

    // MARK: - Configuration

    /// Path to the location.json file
    private let locationFilePath: String

    /// How often to poll for changes (in seconds) - backup for dispatch source
    private let pollInterval: TimeInterval

    /// Callback when location changes
    private let onLocationChanged: (LocationUpdate) -> Void

    // MARK: - State

    /// Last known modification date
    private var lastModificationDate: Date?

    /// Last known location (to detect actual changes, not just file touches)
    private var lastLocation: (lat: Double, lon: Double)?

    /// Dispatch source for file monitoring
    private var fileSource: DispatchSourceFileSystemObject?

    /// File descriptor
    private var fileDescriptor: Int32 = -1

    /// Polling timer (backup)
    private var pollTimer: Timer?

    /// Flag to stop watching
    private var shouldStop = false

    // MARK: - Initialization

    init(
        locationFilePath: String = MindPaths.mindPath("state/location.json"),
        pollInterval: TimeInterval = 5,
        onLocationChanged: @escaping (LocationUpdate) -> Void
    ) {
        self.locationFilePath = locationFilePath
        self.pollInterval = pollInterval
        self.onLocationChanged = onLocationChanged
    }

    deinit {
        stop()
    }

    // MARK: - Public Interface

    /// Start watching for location changes
    func start() {
        shouldStop = false

        // Read initial state
        if let location = readLocation() {
            lastLocation = (lat: location.latitude, lon: location.longitude)
            log("Initialized with location: \(location.latitude), \(location.longitude)", level: .debug, component: "LocationFileWatcher")
        }

        // Try to set up dispatch source for efficient file monitoring
        setupDispatchSource()

        // Also set up polling as a backup (dispatch source may not always fire)
        setupPolling()

        log("Started watching \(locationFilePath)", level: .info, component: "LocationFileWatcher")
    }

    /// Stop watching
    func stop() {
        shouldStop = true

        // Cancel dispatch source
        fileSource?.cancel()
        fileSource = nil

        // Close file descriptor
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        // Cancel polling timer
        pollTimer?.invalidate()
        pollTimer = nil

        log("Stopped watching", level: .info, component: "LocationFileWatcher")
    }

    /// Manually check current location
    func currentLocation() -> LocationUpdate? {
        return readLocation()
    }

    // MARK: - Private Methods

    private func setupDispatchSource() {
        // Open file for reading
        fileDescriptor = open(locationFilePath, O_RDONLY)
        guard fileDescriptor != -1 else {
            log("Could not open file for monitoring: \(locationFilePath)", level: .warn, component: "LocationFileWatcher")
            return
        }

        // Create dispatch source to monitor file changes
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.checkForChanges()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileSource = source

        log("Dispatch source monitoring active", level: .debug, component: "LocationFileWatcher")
    }

    private func setupPolling() {
        // Use RunLoop timer for backup polling
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                self?.checkForChanges()
            }
        }
    }

    private func checkForChanges() {
        guard !shouldStop else { return }

        guard let location = readLocation() else {
            return
        }

        // Check if location actually changed (not just timestamp)
        let hasChanged: Bool
        if let last = lastLocation {
            // Consider it changed if moved more than ~10 meters
            let latDiff = abs(location.latitude - last.lat)
            let lonDiff = abs(location.longitude - last.lon)
            hasChanged = latDiff > 0.0001 || lonDiff > 0.0001
        } else {
            hasChanged = true
        }

        if hasChanged {
            log("Location changed: \(location.latitude), \(location.longitude) (wifi: \(location.wifi ?? "none"))", level: .debug, component: "LocationFileWatcher")
            lastLocation = (lat: location.latitude, lon: location.longitude)

            // Dispatch callback on main queue
            DispatchQueue.main.async { [weak self] in
                self?.onLocationChanged(location)
            }
        }
    }

    private func readLocation() -> LocationUpdate? {
        guard FileManager.default.fileExists(atPath: locationFilePath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: locationFilePath))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let json = json,
                  let lat = json["lat"] as? Double,
                  let lon = json["lon"] as? Double else {
                return nil
            }

            // Parse timestamp
            var timestamp = Date()
            if let timestampStr = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: timestampStr) {
                    timestamp = parsed
                } else {
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    if let parsed = formatter.date(from: timestampStr) {
                        timestamp = parsed
                    }
                }
            }

            return LocationUpdate(
                timestamp: timestamp,
                latitude: lat,
                longitude: lon,
                altitude: json["altitude"] as? Double,
                speed: json["speed"] as? Double,
                battery: json["battery"] as? Double,
                wifi: json["wifi"] as? String,
                motion: json["motion"] as? [String] ?? []
            )
        } catch {
            log("Error reading location file: \(error)", level: .warn, component: "LocationFileWatcher")
            return nil
        }
    }
}
