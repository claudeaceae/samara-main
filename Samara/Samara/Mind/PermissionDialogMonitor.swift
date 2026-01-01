import Foundation

/// Monitors for macOS permission dialogs and notifies É when manual intervention is needed
final class PermissionDialogMonitor {

    /// Polling interval for checking dialogs
    private let pollInterval: TimeInterval = 3.0

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

            // Only check for dialogs if Claude is currently working (lock is held)
            guard TaskLock.isLocked() else {
                continue
            }

            // Check for permission dialogs
            if let dialogInfo = detectPermissionDialog() {
                handleDetectedDialog(dialogInfo)
            }
        }
    }

    /// Detect if there's a permission dialog showing
    /// Returns a description of the dialog if found, nil otherwise
    private func detectPermissionDialog() -> String? {
        // Use AppleScript to check for permission-related windows
        // These typically come from UserNotificationCenter or CoreServicesUIAgent
        let script = """
            tell application "System Events"
                set dialogInfo to ""

                -- Check for TCC/permission dialogs (CoreServicesUIAgent)
                if exists process "CoreServicesUIAgent" then
                    tell process "CoreServicesUIAgent"
                        if exists window 1 then
                            set dialogInfo to name of window 1
                        end if
                    end tell
                end if

                -- Check for UserNotificationCenter dialogs
                if dialogInfo is "" then
                    if exists process "UserNotificationCenter" then
                        tell process "UserNotificationCenter"
                            if exists window 1 then
                                set dialogInfo to name of window 1
                            end if
                        end tell
                    end if
                end if

                -- Check for system preferences prompts
                if dialogInfo is "" then
                    if exists process "System Preferences" then
                        tell process "System Preferences"
                            repeat with w in windows
                                if name of w contains "access" or name of w contains "permission" then
                                    set dialogInfo to name of w
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end if
                end if

                -- Also check System Settings (macOS Ventura+)
                if dialogInfo is "" then
                    if exists process "System Settings" then
                        tell process "System Settings"
                            repeat with w in windows
                                if name of w contains "access" or name of w contains "permission" then
                                    set dialogInfo to name of w
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end if
                end if

                return dialogInfo
            end tell
            """

        let process = Process()
        let outputPipe = Pipe()

        // Ensure pipe is closed to prevent file descriptor leaks
        let outputHandle = outputPipe.fileHandleForReading
        defer {
            try? outputHandle.close()
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputHandle.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Return the dialog info if we found something
            if !output.isEmpty && output != "missing value" {
                return output
            }
        } catch {
            // Silently fail - don't want to spam logs
        }

        return nil
    }

    /// Handle a detected permission dialog
    private func handleDetectedDialog(_ dialogInfo: String) {
        notifiedLock.lock()
        defer { notifiedLock.unlock() }

        // Create a key for this dialog type (normalize to avoid duplicates)
        let dialogKey = normalizeDialogKey(dialogInfo)

        // Check cooldown
        if let lastTime = lastNotificationTime[dialogKey] {
            if Date().timeIntervalSince(lastTime) < notificationCooldown {
                // Still in cooldown, don't notify again
                return
            }
        }

        // Send notification to É
        let message = buildNotificationMessage(dialogInfo)
        log("Detected permission dialog: \(dialogInfo)", level: .info, component: "PermissionDialogMonitor")

        sendMessage(message)

        // Record that we notified
        lastNotificationTime[dialogKey] = Date()
    }

    /// Normalize dialog info to create a consistent key
    private func normalizeDialogKey(_ dialogInfo: String) -> String {
        // Extract the app name or permission type from the dialog
        let lowercased = dialogInfo.lowercased()

        if lowercased.contains("contacts") {
            return "contacts"
        } else if lowercased.contains("calendar") {
            return "calendar"
        } else if lowercased.contains("reminders") {
            return "reminders"
        } else if lowercased.contains("photos") {
            return "photos"
        } else if lowercased.contains("location") {
            return "location"
        } else if lowercased.contains("microphone") {
            return "microphone"
        } else if lowercased.contains("camera") {
            return "camera"
        } else if lowercased.contains("automation") || lowercased.contains("control") {
            return "automation"
        } else if lowercased.contains("accessibility") {
            return "accessibility"
        } else if lowercased.contains("disk") || lowercased.contains("files") {
            return "disk"
        }

        // Use the first few words as the key
        return String(dialogInfo.prefix(30))
    }

    /// Build a user-friendly notification message
    private func buildNotificationMessage(_ dialogInfo: String) -> String {
        let dialogKey = normalizeDialogKey(dialogInfo)
        let currentTask = TaskLock.taskDescription()

        var baseMessage = "Hey, I'm stuck on a permission dialog"

        // Add context about what permission
        switch dialogKey {
        case "contacts":
            baseMessage = "Need your help! There's a Contacts permission dialog on the Mac"
        case "calendar":
            baseMessage = "Need your help! There's a Calendar permission dialog on the Mac"
        case "reminders":
            baseMessage = "Need your help! There's a Reminders permission dialog on the Mac"
        case "photos":
            baseMessage = "Need your help! There's a Photos permission dialog on the Mac"
        case "automation":
            baseMessage = "Need your help! There's an Automation permission dialog on the Mac"
        case "accessibility":
            baseMessage = "Need your help! There's an Accessibility permission dialog on the Mac"
        case "disk":
            baseMessage = "Need your help! There's a disk access permission dialog on the Mac"
        default:
            baseMessage = "Need your help! There's a permission dialog on the Mac"
        }

        // Add what I was trying to do
        baseMessage += " - was in the middle of \(currentTask). Can you approve it?"

        return baseMessage
    }
}
