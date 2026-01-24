import Foundation

/// Watches ~/.claude-mind/senses/ for *.event.json files from satellite services
/// Uses DispatchSource for efficient file system monitoring with polling backup
final class SenseDirectoryWatcher {

    // MARK: - Configuration

    /// Path to the senses directory
    private let sensesDirectory: String

    /// How often to poll for changes (backup for dispatch source)
    private let pollInterval: TimeInterval

    /// Callback when a sense event is detected
    private let onSenseEvent: (SenseEvent) -> Void

    // MARK: - State

    /// Track processed events to avoid duplicates (filename -> last modification date)
    private var processedFiles: [String: Date] = [:]

    /// Lock for thread-safe access to processedFiles
    private let processedLock = NSLock()

    /// Dispatch source for directory monitoring
    private var directorySource: DispatchSourceFileSystemObject?

    /// File descriptor for the directory
    private var directoryDescriptor: Int32 = -1

    /// Polling timer (backup)
    private var pollTimer: Timer?

    /// Flag to stop watching
    private var shouldStop = false

    // MARK: - Initialization

    init(
        sensesDirectory: String = MindPaths.systemPath("senses"),
        pollInterval: TimeInterval = 5,
        onSenseEvent: @escaping (SenseEvent) -> Void
    ) {
        self.sensesDirectory = sensesDirectory
        self.pollInterval = pollInterval
        self.onSenseEvent = onSenseEvent
    }

    deinit {
        stop()
    }

    // MARK: - Public Interface

    /// Start watching for sense events
    func start() {
        shouldStop = false

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: sensesDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Scan for any existing event files (don't process - just mark as seen)
        scanExistingFiles()

        // Set up dispatch source for efficient directory monitoring
        setupDispatchSource()

        // Also set up polling as backup (dispatch source may miss some events)
        setupPolling()

        log("Started watching \(sensesDirectory)", level: .info, component: "SenseDirectoryWatcher")
    }

    /// Stop watching
    func stop() {
        shouldStop = true

        // Cancel dispatch source
        directorySource?.cancel()
        directorySource = nil

        // Close directory descriptor
        if directoryDescriptor != -1 {
            close(directoryDescriptor)
            directoryDescriptor = -1
        }

        // Cancel polling timer
        pollTimer?.invalidate()
        pollTimer = nil

        log("Stopped watching", level: .info, component: "SenseDirectoryWatcher")
    }

    // MARK: - Private Methods

    private func setupDispatchSource() {
        // Open directory for monitoring
        directoryDescriptor = open(sensesDirectory, O_EVTONLY)
        guard directoryDescriptor != -1 else {
            log("Could not open directory for monitoring: \(sensesDirectory)", level: .warn, component: "SenseDirectoryWatcher")
            return
        }

        // Create dispatch source to monitor directory changes
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .extend, .attrib, .link],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.checkForNewEvents()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryDescriptor, fd != -1 {
                close(fd)
                self?.directoryDescriptor = -1
            }
        }

        source.resume()
        directorySource = source

        log("Dispatch source monitoring active", level: .debug, component: "SenseDirectoryWatcher")
    }

    private func setupPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                self?.checkForNewEvents()
            }
        }
    }

    /// Scan existing files on startup (mark as seen but don't process)
    private func scanExistingFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sensesDirectory) else {
            return
        }

        processedLock.lock()
        for file in files where file.hasSuffix(".event.json") {
            let path = (sensesDirectory as NSString).appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                processedFiles[file] = modDate
            }
        }
        processedLock.unlock()

        log("Scanned \(processedFiles.count) existing event file(s)", level: .debug, component: "SenseDirectoryWatcher")
    }

    /// Check for new or modified event files
    private func checkForNewEvents() {
        guard !shouldStop else { return }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sensesDirectory) else {
            return
        }

        for file in files where file.hasSuffix(".event.json") {
            let path = (sensesDirectory as NSString).appendingPathComponent(file)

            // Get modification date
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date else {
                continue
            }

            // Check if this is new or modified
            processedLock.lock()
            let lastProcessed = processedFiles[file]
            let isNew = lastProcessed == nil || modDate > lastProcessed!
            if isNew {
                processedFiles[file] = modDate
            }
            processedLock.unlock()

            if isNew {
                processEventFile(at: path, filename: file)
            }
        }

        // Clean up stale entries (files that no longer exist)
        cleanupStaleEntries()
    }

    /// Process a single event file
    private func processEventFile(at path: String, filename: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            let event = try decoder.decode(SenseEvent.self, from: data)

            log("Processing sense event: \(event.sense) (priority: \(event.priority.rawValue))", level: .info, component: "SenseDirectoryWatcher")

            // Delete the file after successful processing
            // This prevents re-processing on restart
            try? FileManager.default.removeItem(atPath: path)

            // Remove from processed tracking
            processedLock.lock()
            processedFiles.removeValue(forKey: filename)
            processedLock.unlock()

            // Dispatch callback on main queue
            DispatchQueue.main.async { [weak self] in
                self?.onSenseEvent(event)
            }

        } catch {
            log("Error processing event file \(filename): \(error)", level: .warn, component: "SenseDirectoryWatcher")

            // Move failed file to a .failed suffix for debugging
            let failedPath = path.replacingOccurrences(of: ".event.json", with: ".failed.json")
            try? FileManager.default.moveItem(atPath: path, toPath: failedPath)
        }
    }

    /// Remove tracking for files that no longer exist
    private func cleanupStaleEntries() {
        processedLock.lock()
        defer { processedLock.unlock() }

        let existingFiles = (try? FileManager.default.contentsOfDirectory(atPath: sensesDirectory)) ?? []
        let existingSet = Set(existingFiles)

        for file in processedFiles.keys {
            if !existingSet.contains(file) {
                processedFiles.removeValue(forKey: file)
            }
        }
    }
}
