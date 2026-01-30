import Foundation
import AppKit
import ApplicationServices

/// Monitors for macOS permission dialogs and auto-approves them (or notifies É if auto-approve fails)
final class PermissionDialogMonitor {

    /// Polling interval for checking dialogs
    private let pollInterval: TimeInterval = 2.0

    /// Callback to send a message to É
    private let sendMessage: (String) -> Void

    /// Background thread for monitoring
    private var monitorThread: Thread?

    /// Flag to stop monitoring
    private var shouldStop = false

    /// Track dialogs we've already notified about (to avoid spam)
    private var notifiedDialogs: Set<String> = []
    private let notifiedLock = NSLock()

    /// Cooldown period after notifying (don't re-notify for same dialog type for 5 minutes)
    private let notificationCooldown: TimeInterval = 300

    /// Last notification time per dialog type
    private var lastNotificationTime: [String: Date] = [:]

    /// Whether to attempt auto-approval (can be disabled for testing)
    var autoApproveEnabled: Bool = true

    init(sendMessage: @escaping (String) -> Void) {
        self.sendMessage = sendMessage
    }

    /// Start monitoring for permission dialogs
    func startMonitoring() {
        guard monitorThread == nil else {
            log("Already monitoring", level: .debug, component: "PermissionDialogMonitor")
            return
        }

        shouldStop = false
        monitorThread = Thread { [weak self] in
            self?.monitorLoop()
        }
        monitorThread?.name = "PermissionDialogMonitor"
        monitorThread?.start()
        log("Started monitoring", level: .info, component: "PermissionDialogMonitor")
    }

    /// Stop monitoring
    func stopMonitoring() {
        shouldStop = true
        monitorThread = nil
        log("Stopped monitoring", level: .info, component: "PermissionDialogMonitor")
    }

    /// Main monitoring loop
    private func monitorLoop() {
        while !shouldStop {
            Thread.sleep(forTimeInterval: pollInterval)

            // Check for permission dialogs (even if not actively working - dialog might be blocking)
            if let dialogInfo = detectPermissionDialogNative() {
                handleDetectedDialog(dialogInfo)
            }
        }
    }

    // MARK: - Native AX-based Dialog Detection

    /// Process names that host permission dialogs
    private let dialogProcessNames = [
        "CoreServicesUIAgent",
        "UserNotificationCenter",
        "SecurityAgent"
    ]

    /// Detect permission dialogs using native Accessibility APIs
    private func detectPermissionDialogNative() -> DialogInfo? {
        // Get running apps
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        for processName in dialogProcessNames {
            if let app = runningApps.first(where: { $0.localizedName == processName }),
               let dialogInfo = checkAppForPermissionDialog(app) {
                return dialogInfo
            }
        }

        return nil
    }

    /// Check a specific app for permission dialogs
    private func checkAppForPermissionDialog(_ app: NSRunningApplication) -> DialogInfo? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get windows
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            if let dialogInfo = analyzeWindowForPermissionDialog(window, processName: app.localizedName ?? "Unknown") {
                return dialogInfo
            }
        }

        return nil
    }

    /// Analyze a window to see if it's a permission dialog
    private func analyzeWindowForPermissionDialog(_ window: AXUIElement, processName: String) -> DialogInfo? {
        // Get window title/description
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String ?? ""

        // Get all text content from the window to identify what kind of permission
        var textVisited = Set<String>()
        let allText = getAllTextFromElement(window, visited: &textVisited)
        let combinedText = ([title] + allText).joined(separator: " ").lowercased()

        // Check if this looks like a permission dialog
        let permissionKeywords = ["wants to access", "wants access", "would like to", "permission", "allow", "don't allow"]
        let isPermissionDialog = permissionKeywords.contains { combinedText.contains($0) }

        guard isPermissionDialog else {
            return nil
        }

        // Find the Allow button
        var buttonVisited = Set<String>()
        let allowButton = findAllowButton(in: window, visited: &buttonVisited)

        // Determine permission type
        let permissionType = identifyPermissionType(from: combinedText)

        return DialogInfo(
            windowElement: window,
            processName: processName,
            title: title,
            permissionType: permissionType,
            fullText: combinedText,
            allowButton: allowButton
        )
    }

    /// Generate a unique hash for an AXUIElement for cycle detection
    private func getElementHash(_ element: AXUIElement) -> String {
        // Use element's position, size, and role as a reasonable proxy for identity
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

    /// Recursively get all text content from a UI element
    private func getAllTextFromElement(
        _ element: AXUIElement,
        visited: inout Set<String>,
        depth: Int = 0,
        maxDepth: Int = 50
    ) -> [String] {
        // Depth limit
        guard depth < maxDepth else { return [] }

        // Cycle detection using element hash
        let elementHash = getElementHash(element)
        guard !visited.contains(elementHash) else { return [] }
        visited.insert(elementHash)
        var texts: [String] = []

        // Get this element's value/title/description
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] as [CFString] {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
               let text = value as? String, !text.isEmpty {
                texts.append(text)
            }
        }

        // Get children
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                texts.append(contentsOf: getAllTextFromElement(child, visited: &visited, depth: depth + 1, maxDepth: maxDepth))
            }
        }

        return texts
    }

    /// Find the "Allow" button in a dialog
    private func findAllowButton(
        in element: AXUIElement,
        visited: inout Set<String>,
        depth: Int = 0,
        maxDepth: Int = 50
    ) -> AXUIElement? {
        // Depth limit
        guard depth < maxDepth else { return nil }

        // Cycle detection
        let elementHash = getElementHash(element)
        guard !visited.contains(elementHash) else { return nil }
        visited.insert(elementHash)

        // Check if this element is the Allow button
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        if role == kAXButtonRole as String {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            let title = (titleValue as? String)?.lowercased() ?? ""

            if title == "allow" || title == "ok" || title == "approve" {
                return element
            }
        }

        // Recursively check children
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let button = findAllowButton(in: child, visited: &visited, depth: depth + 1, maxDepth: maxDepth) {
                    return button
                }
            }
        }

        return nil
    }

    /// Identify the type of permission from dialog text
    private func identifyPermissionType(from text: String) -> PermissionType {
        if text.contains("contacts") {
            return .contacts
        } else if text.contains("calendar") {
            return .calendar
        } else if text.contains("reminders") {
            return .reminders
        } else if text.contains("photos") {
            return .photos
        } else if text.contains("location") {
            return .location
        } else if text.contains("microphone") {
            return .microphone
        } else if text.contains("camera") {
            return .camera
        } else if text.contains("accessibility") {
            return .accessibility
        } else if text.contains("full disk") || text.contains("files and folders") {
            return .disk
        } else if text.contains("control") || text.contains("automation") || text.contains("messages") {
            return .automation
        }
        return .unknown
    }

    // MARK: - Dialog Handling

    /// Handle a detected permission dialog
    private func handleDetectedDialog(_ dialogInfo: DialogInfo) {
        notifiedLock.lock()
        defer { notifiedLock.unlock() }

        let dialogKey = dialogInfo.permissionType.rawValue

        // Check cooldown
        if let lastTime = lastNotificationTime[dialogKey] {
            if Date().timeIntervalSince(lastTime) < notificationCooldown {
                return
            }
        }

        log("Detected permission dialog: \(dialogInfo.permissionType.rawValue) from \(dialogInfo.processName)",
            level: .info, component: "PermissionDialogMonitor")

        // Attempt auto-approve if enabled and we found the Allow button
        if autoApproveEnabled, let allowButton = dialogInfo.allowButton {
            let approved = attemptAutoApprove(button: allowButton, dialogInfo: dialogInfo)
            if approved {
                log("Auto-approved \(dialogInfo.permissionType.rawValue) permission",
                    level: .info, component: "PermissionDialogMonitor")
                // Still notify but with success message
                sendMessage("Heads up: auto-approved a \(dialogInfo.permissionType.displayName) permission dialog (from Claude Code update)")
                lastNotificationTime[dialogKey] = Date()
                return
            }
        }

        // Fall back to notification
        let message = buildNotificationMessage(dialogInfo)
        sendMessage(message)
        lastNotificationTime[dialogKey] = Date()
    }

    /// Attempt to click the Allow button
    private func attemptAutoApprove(button: AXUIElement, dialogInfo: DialogInfo) -> Bool {
        // Verify the button is enabled
        var enabledValue: AnyObject?
        AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &enabledValue)
        let isEnabled = (enabledValue as? Bool) ?? true

        guard isEnabled else {
            log("Allow button is disabled", level: .debug, component: "PermissionDialogMonitor")
            return false
        }

        // Perform the press action
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)

        if result == .success {
            log("Successfully pressed Allow button", level: .info, component: "PermissionDialogMonitor")
            return true
        } else {
            log("Failed to press Allow button: \(result.rawValue)", level: .warn, component: "PermissionDialogMonitor")
            return false
        }
    }

    /// Build a user-friendly notification message
    private func buildNotificationMessage(_ dialogInfo: DialogInfo) -> String {
        let currentTask = TaskLock.taskDescription()

        var baseMessage = "Need your help! There's a \(dialogInfo.permissionType.displayName) permission dialog on the Mac"

        if dialogInfo.allowButton == nil {
            baseMessage += " (couldn't find Allow button to auto-approve)"
        } else {
            baseMessage += " (auto-approve failed)"
        }

        baseMessage += " - was in the middle of \(currentTask). Can you approve it?"

        return baseMessage
    }

    // MARK: - Types

    struct DialogInfo {
        let windowElement: AXUIElement
        let processName: String
        let title: String
        let permissionType: PermissionType
        let fullText: String
        let allowButton: AXUIElement?
    }

    enum PermissionType: String {
        case contacts
        case calendar
        case reminders
        case photos
        case location
        case microphone
        case camera
        case automation
        case accessibility
        case disk
        case unknown

        var displayName: String {
            switch self {
            case .contacts: return "Contacts"
            case .calendar: return "Calendar"
            case .reminders: return "Reminders"
            case .photos: return "Photos"
            case .location: return "Location"
            case .microphone: return "Microphone"
            case .camera: return "Camera"
            case .automation: return "Automation/Messages"
            case .accessibility: return "Accessibility"
            case .disk: return "Disk Access"
            case .unknown: return "system"
            }
        }
    }
}
