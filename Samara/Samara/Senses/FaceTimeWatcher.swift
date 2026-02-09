import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Watches for incoming FaceTime calls via system logs and NotificationCenter window presence.
///
/// On macOS 26+, the incoming call notification banner exposes zero accessible UI elements —
/// no buttons, no text. Detection uses callservicesd system logs to identify incoming calls,
/// with NC window count as a fast pre-filter. Caller name falls back to the collaborator name
/// when accessibility returns nothing.
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

        // Detect incoming call
        guard let callerName = detectIncomingCall() else { return }

        log("Incoming call detected: '\(callerName)'", level: .info, component: "FaceTimeWatcher")

        // Check if caller is the collaborator
        if isCollaborator(callerName) {
            log("Call from collaborator '\(callerName)' - auto-answering", level: .info, component: "FaceTimeWatcher")
            isProcessingCall = true

            // Click the Accept button via CGEvent (Samara.app has accessibility TCC access).
            // This must happen from within the Samara process — external binaries lack TCC.
            clickAcceptButton()

            onIncomingCall(callerName)

            // Reset flag after delay (call should be answered or failed by then)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.isProcessingCall = false
            }
        } else {
            log("Call from unknown caller '\(callerName)' - ignoring", level: .info, component: "FaceTimeWatcher")
        }
    }

    /// Detect incoming call using a multi-tier approach:
    /// 1. Quick check: NotificationCenter window count (fast pre-filter)
    /// 2. Accessibility API scan for Accept/Decline buttons (works on older macOS)
    /// 3. System log check for callservicesd "incoming call" events (macOS 26+ fallback)
    private func detectIncomingCall() -> String? {
        // Quick pre-filter: check if NotificationCenter has any windows
        guard let notificationCenter = getNotificationCenterApp() else {
            return nil
        }

        let windows = getWindows(for: notificationCenter)
        if windows.isEmpty {
            return nil
        }

        // Tier 1: Try accessibility API (works on older macOS where buttons are exposed)
        for window in windows {
            if let caller = scanWindowForCallViaAccessibility(window) {
                return caller
            }
        }

        // Tier 2: NC window exists but accessibility found nothing.
        // Check system logs for recent incoming call events from callservicesd.
        if checkSystemLogsForIncomingCall() {
            log("Detected incoming call via system logs (accessibility API returned no elements)", level: .info, component: "FaceTimeWatcher")
            // Can't extract caller name from logs (<private>), use collaborator name
            return collaboratorName
        }

        return nil
    }

    /// Check callservicesd system logs for recent incoming call events
    private func checkSystemLogsForIncomingCall() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--last", "15s",
            "--predicate", "process == \"callservicesd\" AND eventMessage CONTAINS \"incoming call\"",
            "--style", "compact"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("incoming call")
        } catch {
            return false
        }
    }

    /// Accept the incoming call by finding and pressing the Answer button via AXPress.
    /// Retries a few times since the AX tree children may take a moment to populate.
    private func clickAcceptButton() {
        log("Attempting to press Answer button via AXPress", level: .info, component: "FaceTimeWatcher")

        // Retry up to 5 times (total ~5s) — AX tree children aren't always immediately available
        for attempt in 0..<5 {
            if attempt > 0 {
                log("  Retry \(attempt): waiting for AX tree to populate...", level: .info, component: "FaceTimeWatcher")
                usleep(1_000_000) // 1s between retries
            }

            guard let ncApp = getNotificationCenterApp() else { continue }
            let windows = getWindows(for: ncApp)
            if windows.isEmpty { continue }

            for window in windows {
                // Dump tree on first attempt for diagnostics
                if attempt == 0 {
                    dumpAccessibilityTree(window, label: "NC-window")
                }

                // Find the Answer button
                var visited = Set<String>()
                var candidates: [(element: AXUIElement, role: String, description: String?, title: String?, position: CGPoint?)] = []
                collectPressableCandidates(window, visited: &visited, candidates: &candidates)

                // Look for the Answer button specifically
                if let answerCandidate = candidates.first(where: { hasAcceptKeyword(desc: $0.description, title: $0.title) }) {
                    let desc = answerCandidate.description ?? "-"
                    let pos = answerCandidate.position.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?"
                    log("  Found Answer button: desc=\"\(desc)\" pos=\(pos) — pressing", level: .info, component: "FaceTimeWatcher")

                    AXUIElementPerformAction(answerCandidate.element, kAXPressAction as CFString)
                    log("  Answer button pressed, call should be connecting", level: .info, component: "FaceTimeWatcher")
                    return
                }

                log("  Attempt \(attempt): \(candidates.count) pressable elements, none matched answer keyword", level: .info, component: "FaceTimeWatcher")
            }
        }

        log("Could not find Answer button after 5 attempts", level: .info, component: "FaceTimeWatcher")
    }

    /// Scan window for call using accessibility API (Tier 1 — pre-macOS 26)
    private func scanWindowForCallViaAccessibility(_ window: AXUIElement) -> String? {
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard result == .success,
              let elements = children as? [AXUIElement] else {
            return nil
        }

        var hasAccept = false
        var hasDecline = false
        var callerName: String?

        scanElements(elements, hasAccept: &hasAccept, hasDecline: &hasDecline, callerName: &callerName)

        if hasAccept && hasDecline {
            return callerName ?? "Unknown"
        }

        if !elements.isEmpty {
            log("NC window has \(elements.count) children but no Accept/Decline found", level: .info, component: "FaceTimeWatcher")
        }

        return nil
    }

    private func getNotificationCenterApp() -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.localizedName == "Notification Center" }) else {
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

    private func scanElements(
        _ elements: [AXUIElement],
        hasAccept: inout Bool,
        hasDecline: inout Bool,
        callerName: inout String?
    ) {
        for element in elements {
            if let description = getElementDescription(element) {
                if description == "Accept" {
                    hasAccept = true
                } else if description == "Decline" {
                    hasDecline = true
                }
            }

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

    // MARK: - Accessibility Helpers

    private func getElementActions(_ element: AXUIElement) -> [String] {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let actionList = actions as? [String] else {
            return []
        }
        return actionList
    }

    private func getElementPosition(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func getElementSize(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func getElementTitle(_ element: AXUIElement) -> String? {
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        return title as? String
    }

    private func getElementSubrole(_ element: AXUIElement) -> String? {
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else {
            return nil
        }
        return subrole as? String
    }

    private func getElementIdentifier(_ element: AXUIElement) -> String? {
        var identifier: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success else {
            return nil
        }
        return identifier as? String
    }

    /// Generate a unique hash for cycle detection (pattern from PermissionDialogMonitor)
    private func getElementHash(_ element: AXUIElement) -> String {
        var position: AnyObject?
        var size: AnyObject?
        var role: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        let posStr = position.map { "\($0)" } ?? "none"
        let sizeStr = size.map { "\($0)" } ?? "none"
        let roleStr = (role as? String) ?? "none"

        return "\(roleStr):\(posStr):\(sizeStr)"
    }

    // MARK: - AX Tree Diagnostics

    /// Dump the full accessibility tree of an element for diagnostic purposes.
    /// Logs role, subrole, description, title, identifier, position, size, and actions for each node.
    private func dumpAccessibilityTree(_ element: AXUIElement, label: String) {
        var visited = Set<String>()
        dumpAccessibilityTreeRecursive(element, label: label, depth: 0, visited: &visited)
    }

    private func dumpAccessibilityTreeRecursive(
        _ element: AXUIElement,
        label: String,
        depth: Int,
        visited: inout Set<String>
    ) {
        guard depth < 20 else { return }

        let hash = getElementHash(element)
        guard !visited.contains(hash) else { return }
        visited.insert(hash)

        let indent = String(repeating: "  ", count: depth)
        let role = getElementRole(element) ?? "?"
        let subrole = getElementSubrole(element) ?? "-"
        let desc = getElementDescription(element) ?? "-"
        let title = getElementTitle(element) ?? "-"
        let identifier = getElementIdentifier(element) ?? "-"
        let actions = getElementActions(element)
        let pos = getElementPosition(element)
        let size = getElementSize(element)
        let posStr = pos.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "?"
        let sizeStr = size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"

        log("\(indent)\(label)[\(depth)]: role=\(role) subrole=\(subrole) desc=\"\(desc)\" title=\"\(title)\" id=\"\(identifier)\" pos=\(posStr) size=\(sizeStr) actions=\(actions)", level: .info, component: "FaceTimeWatcher")

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for (i, child) in children.enumerated() {
                dumpAccessibilityTreeRecursive(child, label: "child\(i)", depth: depth + 1, visited: &visited)
            }
        }
    }

    /// Recursively collect all elements that support AXPress
    private func collectPressableCandidates(
        _ element: AXUIElement,
        visited: inout Set<String>,
        candidates: inout [(element: AXUIElement, role: String, description: String?, title: String?, position: CGPoint?)],
        depth: Int = 0
    ) {
        guard depth < 20 else { return }

        let hash = getElementHash(element)
        guard !visited.contains(hash) else { return }
        visited.insert(hash)

        let actions = getElementActions(element)
        if actions.contains(kAXPressAction as String) {
            let role = getElementRole(element) ?? "?"
            let desc = getElementDescription(element)
            let title = getElementTitle(element)
            let pos = getElementPosition(element)
            candidates.append((element: element, role: role, description: desc, title: title, position: pos))
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectPressableCandidates(child, visited: &visited, candidates: &candidates, depth: depth + 1)
            }
        }
    }

    // MARK: - Acceptance Helpers

    private func notificationDismissed() -> Bool {
        let count = getNotificationCenterApp().flatMap { getWindows(for: $0).count } ?? 0
        return count == 0
    }

    private func hasAcceptKeyword(desc: String?, title: String?) -> Bool {
        let combined = ((desc ?? "") + " " + (title ?? "")).lowercased()
        return combined.contains("accept") || combined.contains("answer")
    }

    /// Check if caller matches collaborator (case-insensitive, partial match)
    private func isCollaborator(_ caller: String) -> Bool {
        let callerLower = caller.lowercased()
        let nameLower = collaboratorName.lowercased()

        // Match if either contains the other
        return callerLower.contains(nameLower) || nameLower.contains(callerLower)
    }
}
