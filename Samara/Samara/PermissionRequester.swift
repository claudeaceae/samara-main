import Foundation
import EventKit
import Contacts

/// Requests system permissions on daemon startup
/// No GUI - macOS shows native permission dialogs automatically
///
/// Removed permissions (and why):
/// - Location: Uses file from Overland (LocationFileWatcher), not CoreLocation
/// - Camera: On-demand request in CameraCapture.swift (lines 42-55)
/// - Microphone: Not used in Samara.app
/// - Photos: Not used in Samara.app
/// - Bluetooth: Not used in Samara.app
final class PermissionRequester: NSObject {

    /// Request all permissions. Call once at startup.
    static func requestAllPermissions() {
        log("Checking and requesting permissions...", level: .info, component: "Permissions")

        // PIM (Personal Information Management) - these have no on-demand alternative
        requestCalendarPermission()
        requestRemindersPermission()
        requestContactsPermission()

        // Music (deferred - will be requested on first library access)
        requestMusicPermission()

        // HomeKit requires app bundle with entitlements, skipped for daemon
        log("HomeKit: requires app entitlements, must be granted manually", level: .info, component: "Permissions")

        // Focus status is checked on-demand, no upfront request needed
        log("Focus: will be checked on-demand", level: .info, component: "Permissions")

        // Local network permission is triggered by actual network activity
        log("Local Network: will be triggered on first network discovery", level: .info, component: "Permissions")

        // Camera permission is requested on-demand in CameraCapture.swift
        log("Camera: will be requested on-demand when capture is needed", level: .info, component: "Permissions")
    }

    // MARK: - Calendar

    private static func requestCalendarPermission() {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .notDetermined:
            log("Calendar: not determined, requesting...", level: .info, component: "Permissions")
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, error in
                    if let error = error {
                        log("Calendar error: \(error.localizedDescription)", level: .warn, component: "Permissions")
                    } else {
                        log("Calendar: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
                    }
                }
            } else {
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        log("Calendar error: \(error.localizedDescription)", level: .warn, component: "Permissions")
                    } else {
                        log("Calendar: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
                    }
                }
            }
        case .authorized, .fullAccess:
            log("Calendar: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Calendar: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        case .writeOnly:
            log("Calendar: write-only access", level: .info, component: "Permissions")
        @unknown default:
            log("Calendar: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Reminders

    private static func requestRemindersPermission() {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .notDetermined:
            log("Reminders: not determined, requesting...", level: .info, component: "Permissions")
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { granted, error in
                    if let error = error {
                        log("Reminders error: \(error.localizedDescription)", level: .warn, component: "Permissions")
                    } else {
                        log("Reminders: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
                    }
                }
            } else {
                store.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        log("Reminders error: \(error.localizedDescription)", level: .warn, component: "Permissions")
                    } else {
                        log("Reminders: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
                    }
                }
            }
        case .authorized, .fullAccess:
            log("Reminders: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Reminders: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        case .writeOnly:
            log("Reminders: write-only access", level: .info, component: "Permissions")
        @unknown default:
            log("Reminders: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Contacts

    private static func requestContactsPermission() {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .notDetermined:
            log("Contacts: not determined, requesting...", level: .info, component: "Permissions")
            store.requestAccess(for: .contacts) { granted, error in
                if let error = error {
                    log("Contacts error: \(error.localizedDescription)", level: .warn, component: "Permissions")
                } else {
                    log("Contacts: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
                }
            }
        case .authorized:
            log("Contacts: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Contacts: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        case .limited:
            log("Contacts: limited access", level: .info, component: "Permissions")
        @unknown default:
            log("Contacts: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Apple Music

    private static func requestMusicPermission() {
        // MediaPlayer/MusicKit authorization
        // On macOS, this is typically granted via the usage description
        // The actual permission prompt appears when first accessing the library
        log("Music: will be requested on first library access", level: .info, component: "Permissions")
    }
}
