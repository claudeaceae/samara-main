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
        print("[Permissions] Checking and requesting permissions...")

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
        print("[Permissions] HomeKit: requires app entitlements, must be granted manually")

        // Focus status is checked on-demand, no upfront request needed
        print("[Permissions] Focus: will be checked on-demand")

        // Local network permission is triggered by actual network activity
        print("[Permissions] Local Network: will be triggered on first network discovery")
    }

    // MARK: - Calendar

    private static func requestCalendarPermission() {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .notDetermined:
            print("[Permissions] Calendar: not determined, requesting...")
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, error in
                    if let error = error {
                        print("[Permissions] Calendar error: \(error.localizedDescription)")
                    } else {
                        print("[Permissions] Calendar: \(granted ? "granted" : "denied")")
                    }
                }
            } else {
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        print("[Permissions] Calendar error: \(error.localizedDescription)")
                    } else {
                        print("[Permissions] Calendar: \(granted ? "granted" : "denied")")
                    }
                }
            }
        case .authorized, .fullAccess:
            print("[Permissions] Calendar: already authorized")
        case .denied, .restricted:
            print("[Permissions] Calendar: denied/restricted - user must grant in System Settings")
        case .writeOnly:
            print("[Permissions] Calendar: write-only access")
        @unknown default:
            print("[Permissions] Calendar: unknown status")
        }
    }

    // MARK: - Reminders

    private static func requestRemindersPermission() {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .notDetermined:
            print("[Permissions] Reminders: not determined, requesting...")
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { granted, error in
                    if let error = error {
                        print("[Permissions] Reminders error: \(error.localizedDescription)")
                    } else {
                        print("[Permissions] Reminders: \(granted ? "granted" : "denied")")
                    }
                }
            } else {
                store.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        print("[Permissions] Reminders error: \(error.localizedDescription)")
                    } else {
                        print("[Permissions] Reminders: \(granted ? "granted" : "denied")")
                    }
                }
            }
        case .authorized, .fullAccess:
            print("[Permissions] Reminders: already authorized")
        case .denied, .restricted:
            print("[Permissions] Reminders: denied/restricted - user must grant in System Settings")
        case .writeOnly:
            print("[Permissions] Reminders: write-only access")
        @unknown default:
            print("[Permissions] Reminders: unknown status")
        }
    }

    // MARK: - Contacts

    private static func requestContactsPermission() {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .notDetermined:
            print("[Permissions] Contacts: not determined, requesting...")
            store.requestAccess(for: .contacts) { granted, error in
                if let error = error {
                    print("[Permissions] Contacts error: \(error.localizedDescription)")
                } else {
                    print("[Permissions] Contacts: \(granted ? "granted" : "denied")")
                }
            }
        case .authorized:
            print("[Permissions] Contacts: already authorized")
        case .denied, .restricted:
            print("[Permissions] Contacts: denied/restricted - user must grant in System Settings")
        case .limited:
            print("[Permissions] Contacts: limited access")
        @unknown default:
            print("[Permissions] Contacts: unknown status")
        }
    }

    // MARK: - Location

    private static func requestLocationPermission() {
        let status = CLLocationManager.authorizationStatus()

        switch status {
        case .notDetermined:
            print("[Permissions] Location: not determined, requesting...")
            locationManager = CLLocationManager()
            locationManager?.delegate = permissionRequester
            locationManager?.requestAlwaysAuthorization()
        case .authorized, .authorizedAlways:
            print("[Permissions] Location: already authorized")
        case .denied, .restricted:
            print("[Permissions] Location: denied/restricted - user must grant in System Settings")
        @unknown default:
            print("[Permissions] Location: unknown status")
        }
    }

    // MARK: - Photos

    private static func requestPhotosPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .notDetermined:
            print("[Permissions] Photos: not determined, requesting...")
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                print("[Permissions] Photos: \(newStatus == .authorized ? "granted" : "denied/limited")")
            }
        case .authorized:
            print("[Permissions] Photos: already authorized")
        case .limited:
            print("[Permissions] Photos: limited access")
        case .denied, .restricted:
            print("[Permissions] Photos: denied/restricted - user must grant in System Settings")
        @unknown default:
            print("[Permissions] Photos: unknown status")
        }
    }

    // MARK: - Apple Music

    private static func requestMusicPermission() {
        // MediaPlayer/MusicKit authorization
        // On macOS, this is typically granted via the usage description
        // The actual permission prompt appears when first accessing the library
        print("[Permissions] Music: will be requested on first library access")
    }

    // MARK: - Camera

    private static func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .notDetermined:
            print("[Permissions] Camera: not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("[Permissions] Camera: \(granted ? "granted" : "denied")")
            }
        case .authorized:
            print("[Permissions] Camera: already authorized")
        case .denied, .restricted:
            print("[Permissions] Camera: denied/restricted - user must grant in System Settings")
        @unknown default:
            print("[Permissions] Camera: unknown status")
        }
    }

    // MARK: - Microphone

    private static func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            print("[Permissions] Microphone: not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("[Permissions] Microphone: \(granted ? "granted" : "denied")")
            }
        case .authorized:
            print("[Permissions] Microphone: already authorized")
        case .denied, .restricted:
            print("[Permissions] Microphone: denied/restricted - user must grant in System Settings")
        @unknown default:
            print("[Permissions] Microphone: unknown status")
        }
    }

    // MARK: - Bluetooth

    private static func requestBluetoothPermission() {
        print("[Permissions] Bluetooth: initializing...")
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
            print("[Permissions] Location: granted")
        case .denied, .restricted:
            print("[Permissions] Location: denied")
        case .notDetermined:
            break // Still waiting
        @unknown default:
            print("[Permissions] Location: unknown status change")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PermissionRequester: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[Permissions] Bluetooth: powered on and authorized")
        case .poweredOff:
            print("[Permissions] Bluetooth: powered off")
        case .unauthorized:
            print("[Permissions] Bluetooth: unauthorized - user must grant in System Settings")
        case .unsupported:
            print("[Permissions] Bluetooth: unsupported on this device")
        case .resetting:
            print("[Permissions] Bluetooth: resetting")
        case .unknown:
            print("[Permissions] Bluetooth: unknown state")
        @unknown default:
            print("[Permissions] Bluetooth: unknown state")
        }
    }
}
