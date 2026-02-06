import Foundation
import AppKit
import ApplicationServices

/// Watches NotificationCenter for incoming FaceTime calls
/// Uses Accessibility API to detect Accept/Decline buttons
final class FaceTimeWatcher {

    private let pollInterval: TimeInterval
    private let onIncomingCall: (String) -> Void
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "samara.facetime.poll", qos: .userInitiated)
    private let collaboratorName: String
    private var isProcessingCall = false

    init(
        collaboratorName: String,
        pollInterval: TimeInterval = 5.0,
        onIncomingCall: @escaping (String) -> Void
    ) {
        self.collaboratorName = collaboratorName
        self.pollInterval = pollInterval
        self.onIncomingCall = onIncomingCall
    }

    func start() {
        log("Starting FaceTime watcher (poll interval: \(pollInterval)s)", level: .info, component: "FaceTimeWatcher")

        pollTimer = DispatchSource.makeTimerSource(queue: pollQueue)
        pollTimer?.schedule(deadline: .now(), repeating: pollInterval)
        pollTimer?.setEventHandler { [weak self] in
            self?.checkForIncomingCall()
        }
        pollTimer?.resume()
    }

    func stop() {
        log("Stopping FaceTime watcher", level: .info, component: "FaceTimeWatcher")
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Private Methods

    private func checkForIncomingCall() {
        // Skip if already processing a call
        guard !isProcessingCall else { return }

        // Detect incoming call banner in NotificationCenter
        guard let callerName = detectIncomingCall() else { return }

        log("Incoming call detected: '\(callerName)'", level: .info, component: "FaceTimeWatcher")

        // Check if caller is the collaborator
        if isCollaborator(callerName) {
            log("Call from collaborator '\(callerName)' - auto-answering", level: .info, component: "FaceTimeWatcher")
            isProcessingCall = true
            onIncomingCall(callerName)

            // Reset flag after delay (call should be answered or failed by then)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.isProcessingCall = false
            }
        } else {
            log("Call from unknown caller '\(callerName)' - ignoring", level: .info, component: "FaceTimeWatcher")
        }
    }

    /// Detect incoming call via Accessibility API
    /// Returns caller name if call detected, nil otherwise
    private func detectIncomingCall() -> String? {
        // Get NotificationCenter process
        guard let notificationCenter = getNotificationCenterApp() else {
            return nil
        }

        // Scan windows for Accept/Decline buttons
        let windows = getWindows(for: notificationCenter)

        for window in windows {
            if let caller = scanWindowForCall(window) {
                return caller
            }
        }

        return nil
    }

    private func getNotificationCenterApp() -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.localizedName == "NotificationCenter" }) else {
            return nil
        }

        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func getWindows(for app: AXUIElement) -> [AXUIElement] {
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)

        guard result == .success,
              let windowArray = windows as? [AXUIElement] else {
            return []
        }

        return windowArray
    }

    private func scanWindowForCall(_ window: AXUIElement) -> String? {
        // Get all UI elements in window
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard result == .success,
              let elements = children as? [AXUIElement] else {
            return nil
        }

        var hasAccept = false
        var hasDecline = false
        var callerName: String?

        // Recursively scan all elements
        scanElements(elements, hasAccept: &hasAccept, hasDecline: &hasDecline, callerName: &callerName)

        // If both buttons found, we have an incoming call
        if hasAccept && hasDecline {
            return callerName ?? "Unknown"
        }

        return nil
    }

    private func scanElements(
        _ elements: [AXUIElement],
        hasAccept: inout Bool,
        hasDecline: inout Bool,
        callerName: inout String?
    ) {
        for element in elements {
            // Check for Accept/Decline buttons
            if let description = getElementDescription(element) {
                if description == "Accept" {
                    hasAccept = true
                } else if description == "Decline" {
                    hasDecline = true
                }
            }

            // Extract caller name from static text elements
            if let role = getElementRole(element), role == kAXStaticTextRole as String {
                if let value = getElementValue(element) as? String,
                   !value.isEmpty,
                   !value.contains("FaceTime"),
                   !value.contains("incoming"),
                   !value.contains("Accept"),
                   !value.contains("Decline") {
                    callerName = value
                }
            }

            // Recursively scan children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let childElements = childrenRef as? [AXUIElement] {
                scanElements(childElements, hasAccept: &hasAccept, hasDecline: &hasDecline, callerName: &callerName)
            }
        }
    }

    private func getElementDescription(_ element: AXUIElement) -> String? {
        var description: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) == .success else {
            return nil
        }
        return description as? String
    }

    private func getElementRole(_ element: AXUIElement) -> String? {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else {
            return nil
        }
        return role as? String
    }

    private func getElementValue(_ element: AXUIElement) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// Check if caller matches collaborator (case-insensitive, partial match)
    private func isCollaborator(_ caller: String) -> Bool {
        let callerLower = caller.lowercased()
        let nameLower = collaboratorName.lowercased()

        // Match if either contains the other
        return callerLower.contains(nameLower) || nameLower.contains(callerLower)
    }
}
