import Foundation
import EventKit
import Contacts
import CoreLocation
import Photos
import AVFoundation
import CoreBluetooth

/// Requests system permissions on daemon startup
/// No GUI - macOS shows native permission dialogs automatically
final class PermissionRequester: NSObject {

    // Keep strong references to managers that need to persist
    private static var locationManager: CLLocationManager?
    private static var bluetoothManager: CBCentralManager?
    private static var permissionRequester: PermissionRequester?

    /// Request all permissions. Call once at startup.
    static func requestAllPermissions() {
        log("Checking and requesting permissions...", level: .info, component: "Permissions")

        // Keep a strong reference to self for delegate callbacks
        permissionRequester = PermissionRequester()

        // PIM (Personal Information Management)
        requestCalendarPermission()
        requestRemindersPermission()
        requestContactsPermission()

        // Location
        requestLocationPermission()

        // Media
        requestPhotosPermission()
        requestMusicPermission()
        requestCameraPermission()
        requestMicrophonePermission()

        // Devices
        requestBluetoothPermission()

        // HomeKit requires app bundle with entitlements, skipped for daemon
        log("HomeKit: requires app entitlements, must be granted manually", level: .info, component: "Permissions")

        // Focus status is checked on-demand, no upfront request needed
        log("Focus: will be checked on-demand", level: .info, component: "Permissions")

        // Local network permission is triggered by actual network activity
        log("Local Network: will be triggered on first network discovery", level: .info, component: "Permissions")
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

    // MARK: - Location

    private static func requestLocationPermission() {
        let status = CLLocationManager.authorizationStatus()

        switch status {
        case .notDetermined:
            log("Location: not determined, requesting...", level: .info, component: "Permissions")
            locationManager = CLLocationManager()
            locationManager?.delegate = permissionRequester
            locationManager?.requestAlwaysAuthorization()
        case .authorized, .authorizedAlways:
            log("Location: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Location: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        @unknown default:
            log("Location: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Photos

    private static func requestPhotosPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .notDetermined:
            log("Photos: not determined, requesting...", level: .info, component: "Permissions")
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                log("Photos: \(newStatus == .authorized ? "granted" : "denied/limited")", level: .info, component: "Permissions")
            }
        case .authorized:
            log("Photos: already authorized", level: .info, component: "Permissions")
        case .limited:
            log("Photos: limited access", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Photos: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        @unknown default:
            log("Photos: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Apple Music

    private static func requestMusicPermission() {
        // MediaPlayer/MusicKit authorization
        // On macOS, this is typically granted via the usage description
        // The actual permission prompt appears when first accessing the library
        log("Music: will be requested on first library access", level: .info, component: "Permissions")
    }

    // MARK: - Camera

    private static func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .notDetermined:
            log("Camera: not determined, requesting...", level: .info, component: "Permissions")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                log("Camera: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
            }
        case .authorized:
            log("Camera: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Camera: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        @unknown default:
            log("Camera: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Microphone

    private static func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            log("Microphone: not determined, requesting...", level: .info, component: "Permissions")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                log("Microphone: \(granted ? "granted" : "denied")", level: .info, component: "Permissions")
            }
        case .authorized:
            log("Microphone: already authorized", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Microphone: denied/restricted - user must grant in System Settings", level: .warn, component: "Permissions")
        @unknown default:
            log("Microphone: unknown status", level: .warn, component: "Permissions")
        }
    }

    // MARK: - Bluetooth

    private static func requestBluetoothPermission() {
        log("Bluetooth: initializing...", level: .info, component: "Permissions")
        // CBCentralManager prompts when created
        bluetoothManager = CBCentralManager(delegate: permissionRequester, queue: nil)
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionRequester: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorized, .authorizedAlways:
            log("Location: granted", level: .info, component: "Permissions")
        case .denied, .restricted:
            log("Location: denied", level: .warn, component: "Permissions")
        case .notDetermined:
            break // Still waiting
        @unknown default:
            log("Location: unknown status change", level: .warn, component: "Permissions")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PermissionRequester: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("Bluetooth: powered on and authorized", level: .info, component: "Permissions")
        case .poweredOff:
            log("Bluetooth: powered off", level: .info, component: "Permissions")
        case .unauthorized:
            log("Bluetooth: unauthorized - user must grant in System Settings", level: .warn, component: "Permissions")
        case .unsupported:
            log("Bluetooth: unsupported on this device", level: .info, component: "Permissions")
        case .resetting:
            log("Bluetooth: resetting", level: .info, component: "Permissions")
        case .unknown:
            log("Bluetooth: unknown state", level: .debug, component: "Permissions")
        @unknown default:
            log("Bluetooth: unknown state", level: .debug, component: "Permissions")
        }
    }
}
