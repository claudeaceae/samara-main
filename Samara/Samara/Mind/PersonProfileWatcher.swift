import Foundation

/// Polls for changes to person profiles and triggers cache invalidation.
final class PersonProfileWatcher {
    private let peopleDirectory: String
    private let legacyDirectory: String
    private let pollInterval: TimeInterval
    private let onProfilesChanged: () -> Void

    private var watchThread: Thread?
    private var shouldStop = false
    private var lastSnapshot: [String: Date] = [:]

    init(
        peopleDirectory: String = MindPaths.mindPath("memory/people"),
        legacyDirectory: String = MindPaths.mindPath("memory"),
        pollInterval: TimeInterval = 15,
        onProfilesChanged: @escaping () -> Void
    ) {
        self.peopleDirectory = peopleDirectory
        self.legacyDirectory = legacyDirectory
        self.pollInterval = pollInterval
        self.onProfilesChanged = onProfilesChanged
    }

    func start() {
        guard watchThread == nil else { return }
        shouldStop = false
        lastSnapshot = snapshot()

        let thread = Thread { [weak self] in
            while let self = self, !self.shouldStop {
                Thread.sleep(forTimeInterval: self.pollInterval)
                if self.shouldStop { break }
                self.checkForChanges()
            }
        }
        thread.qualityOfService = .utility
        thread.start()
        watchThread = thread
        log("Person profile watcher started", level: .info, component: "PersonProfileWatcher")
    }

    func stop() {
        shouldStop = true
        watchThread?.cancel()
        watchThread = nil
        log("Person profile watcher stopped", level: .info, component: "PersonProfileWatcher")
    }

    private func checkForChanges() {
        let latest = snapshot()
        guard hasChanges(latest) else { return }
        lastSnapshot = latest
        onProfilesChanged()
        log("Person profile cache invalidated", level: .debug, component: "PersonProfileWatcher")
    }

    private func hasChanges(_ latest: [String: Date]) -> Bool {
        if latest.count != lastSnapshot.count {
            return true
        }
        for (path, date) in latest {
            if lastSnapshot[path] != date {
                return true
            }
        }
        return false
    }

    private func snapshot() -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default

        if let personDirs = try? fm.contentsOfDirectory(atPath: peopleDirectory) {
            for dir in personDirs where dir != "_template" && !dir.hasPrefix(".") {
                let profilePath = (peopleDirectory as NSString).appendingPathComponent("\(dir)/profile.md")
                if let modDate = modificationDate(path: profilePath) {
                    result[profilePath] = modDate
                }
            }
        }

        if let legacyFiles = try? fm.contentsOfDirectory(atPath: legacyDirectory) {
            for file in legacyFiles where file.hasPrefix("about-") && file.hasSuffix(".md") {
                let legacyPath = (legacyDirectory as NSString).appendingPathComponent(file)
                if let modDate = modificationDate(path: legacyPath) {
                    result[legacyPath] = modDate
                }
            }
        }

        return result
    }

    private func modificationDate(path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }
}
