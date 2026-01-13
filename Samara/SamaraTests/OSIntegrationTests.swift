import AVFoundation
import Contacts
import XCTest

final class OSIntegrationTests: XCTestCase {

    private struct IntegrationConfig: Decodable {
        struct Notes: Decodable {
            let location: String
            let scratchpad: String
        }

        struct Mail: Decodable {
            let account: String
        }

        struct Collaborator: Decodable {
            let name: String
            let phone: String
            let email: String
        }

        let notes: Notes
        let mail: Mail
        let collaborator: Collaborator
    }

    private func requireIntegration(_ flag: String, label: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SAMARA_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set SAMARA_INTEGRATION_TESTS=1 to enable OS integration tests.")
        }
        guard env[flag] == "1" else {
            throw XCTSkip("Set \(flag)=1 to enable \(label) integration test.")
        }
    }

    private func loadIntegrationConfig() throws -> IntegrationConfig {
        let env = ProcessInfo.processInfo.environment
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-mind/config.json")
            .path
        let rawPath = env["SAMARA_INTEGRATION_CONFIG_PATH"] ?? defaultPath
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Config not found at \(url.path). Set SAMARA_INTEGRATION_CONFIG_PATH to override.")
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(IntegrationConfig.self, from: data)
    }

    func testNotesIntegrationReadsConfiguredNotes() throws {
        try requireIntegration("SAMARA_INTEGRATION_NOTES", label: "Notes")
        let config = try loadIntegrationConfig()

        let watcher = NoteWatcher(
            watchedNotes: [config.notes.location, config.notes.scratchpad],
            pollInterval: 60
        ) { _ in }

        let location = watcher.checkNote(named: config.notes.location)
        XCTAssertNotNil(location, "Missing note: \(config.notes.location)")

        let scratchpad = watcher.checkNote(named: config.notes.scratchpad)
        XCTAssertNotNil(scratchpad, "Missing note: \(config.notes.scratchpad)")
    }

    func testMailIntegrationFetchesRecentEmails() throws {
        try requireIntegration("SAMARA_INTEGRATION_MAIL", label: "Mail")
        let config = try loadIntegrationConfig()

        let mailStore = MailStore(
            targetEmails: [config.collaborator.email],
            accountName: config.mail.account
        )

        _ = try mailStore.fetchRecentEmails(limit: 1)
    }

    func testContactsIntegrationResolvesCollaborator() throws {
        try requireIntegration("SAMARA_INTEGRATION_CONTACTS", label: "Contacts")

        let status = CNContactStore.authorizationStatus(for: .contacts)
        reportContactsStatus(status)
        if status == .notDetermined {
            let accessResult = requestContactsAccess()
            if accessResult != .completed {
                throw XCTSkip("Contacts access prompt timed out; check permissions.")
            }
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw XCTSkip("Grant Contacts access to run the integration test.")
        }

        if let containerCount = preflightContactsStore() {
            XCTContext.runActivity(named: "Contacts containers visible: \(containerCount)") { _ in }
        } else {
            throw XCTSkip("Contacts store did not respond; contactsd may be unavailable.")
        }

        let config = try loadIntegrationConfig()
        let handles = [config.collaborator.email, config.collaborator.phone]
            .filter { !$0.isEmpty }
        guard let resolved = resolveContacts(handles: handles) else {
            throw XCTSkip("Contacts lookup timed out; check permissions and contactsd availability.")
        }

        XCTAssertFalse(resolved.isEmpty, "Collaborator not found in Contacts for configured handles.")
    }

    @MainActor
    func testCameraIntegrationCapturesImage() async throws {
        try requireIntegration("SAMARA_INTEGRATION_CAMERA", label: "Camera")

        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw XCTSkip("Grant camera access to run the integration test.")
            }
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }

        guard status == .authorized else {
            throw XCTSkip("Grant camera access to run the integration test.")
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        guard !discovery.devices.isEmpty else {
            throw XCTSkip("No camera devices available for capture.")
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-camera-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let outputURL = outputDir.appendingPathComponent("capture.jpg")
        let capture = CameraCapture()
        let path = try await capture.capture(to: outputURL.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber ?? 0
        XCTAssertTrue(size.intValue > 0)
    }

    private func requestContactsAccess(timeout: TimeInterval = 30) -> XCTWaiter.Result {
        let expectation = expectation(description: "contacts-access")
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            expectation.fulfill()
        }
        return XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    private func resolveContacts(handles: [String], timeout: TimeInterval = 60) -> [String]? {
        guard !handles.isEmpty else { return [] }

        let expectation = expectation(description: "contacts")
        var resolved: [String] = []

        DispatchQueue.global(qos: .userInitiated).async {
            let resolver = ContactsResolver()
            let output = handles.compactMap { resolver.resolveName(for: $0) }
            DispatchQueue.main.async {
                resolved = output
                expectation.fulfill()
            }
        }

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result != .completed {
            return nil
        }

        return resolved
    }

    private func preflightContactsStore(timeout: TimeInterval = 10) -> Int? {
        let expectation = expectation(description: "contacts-preflight")
        var count: Int?

        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            do {
                let containers = try store.containers(matching: nil)
                count = containers.count
            } catch {
                count = nil
            }
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        }

        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed ? count : nil
    }

    private func reportContactsStatus(_ status: CNAuthorizationStatus) {
        let label: String
        switch status {
        case .notDetermined:
            label = "notDetermined"
        case .restricted:
            label = "restricted"
        case .denied:
            label = "denied"
        case .authorized:
            label = "authorized"
        case .limited:
            label = "limited"
        @unknown default:
            label = "unknown"
        }
        XCTContext.runActivity(named: "Contacts authorization status: \(label)") { _ in }
    }
}
