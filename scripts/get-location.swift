#!/usr/bin/env swift

import CoreLocation
import Foundation

class LocationFetcher: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    let semaphore = DispatchSemaphore(value: 0)
    var location: CLLocation?
    var error: Error?
    var authGranted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func fetch() -> CLLocation? {
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            // Request authorization and wait
            fputs("Requesting location authorization...\n", stderr)
            manager.requestAlwaysAuthorization()
            // Wait for authorization callback
            let authResult = semaphore.wait(timeout: .now() + 30)
            if authResult == .timedOut || !authGranted {
                fputs("Error: Authorization not granted or timed out\n", stderr)
                return nil
            }
        case .authorized, .authorizedAlways:
            authGranted = true
        case .denied, .restricted:
            fputs("Error: Location access denied. Please enable in System Settings > Privacy & Security > Location Services\n", stderr)
            return nil
        @unknown default:
            fputs("Error: Unknown authorization status: \(status.rawValue)\n", stderr)
            return nil
        }

        // Now request location
        fputs("Requesting location...\n", stderr)
        manager.requestLocation()

        // Wait up to 10 seconds for location
        let result = semaphore.wait(timeout: .now() + 10)
        if result == .timedOut {
            fputs("Error: Location request timed out\n", stderr)
            return nil
        }

        return location
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        fputs("Authorization changed to: \(status.rawValue)\n", stderr)
        if status == .authorized || status == .authorizedAlways {
            authGranted = true
            semaphore.signal()
        } else if status == .denied || status == .restricted {
            authGranted = false
            semaphore.signal()
        }
        // If still notDetermined, keep waiting
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
        semaphore.signal()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error
        fputs("Error getting location: \(error.localizedDescription)\n", stderr)
        semaphore.signal()
    }
}

let fetcher = LocationFetcher()
if let loc = fetcher.fetch() {
    print("Latitude: \(loc.coordinate.latitude)")
    print("Longitude: \(loc.coordinate.longitude)")
    print("Altitude: \(loc.altitude) meters")
    print("Horizontal Accuracy: \(loc.horizontalAccuracy) meters")
    if let floor = loc.floor {
        print("Floor: \(floor.level)")
    }
    print("Timestamp: \(loc.timestamp)")
} else {
    exit(1)
}
