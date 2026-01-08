import Foundation
import MapKit
import CoreLocation

/// Provides reverse geocoding with caching for location-based messaging
final class ReverseGeocoder {

    // MARK: - Types

    struct CachedAddress {
        let address: String
        let timestamp: Date
        let latitude: Double
        let longitude: Double
    }

    // MARK: - Configuration

    /// Cache radius in meters - if within this distance of a cached location, reuse the address
    private let cacheRadius: Double = 100

    /// Cache expiry time (24 hours)
    private let cacheExpiry: TimeInterval = 24 * 60 * 60

    /// Maximum cache size
    private let maxCacheSize = 100

    // MARK: - State

    private var cache: [CachedAddress] = []
    private let queue = DispatchQueue(label: "co.organelle.samara.geocoder")

    // MARK: - Singleton

    static let shared = ReverseGeocoder()

    private init() {}

    // MARK: - Public Interface

    /// Get a human-readable address for coordinates
    /// Falls back to coordinate string if geocoding fails
    func address(for latitude: Double, longitude: Double, completion: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(self?.formatCoordinates(latitude, longitude) ?? "unknown location")
                return
            }

            // Check cache first
            if let cached = self.findCached(lat: latitude, lon: longitude) {
                log("Using cached address for (\(latitude), \(longitude)): \(cached)", level: .debug, component: "ReverseGeocoder")
                DispatchQueue.main.async {
                    completion(cached)
                }
                return
            }

            // Perform reverse geocoding using MapKit
            let location = CLLocation(latitude: latitude, longitude: longitude)

            if let request = MKReverseGeocodingRequest(location: location) {
                Task {
                    do {
                        let results = try await request.mapItems
                        if let mapItem = results.first {
                            let address = self.formatMapItem(mapItem)

                            // Cache the result
                            self.queue.async {
                                self.addToCache(address: address, lat: latitude, lon: longitude)
                            }

                            log("Geocoded (\(latitude), \(longitude)): \(address)", level: .debug, component: "ReverseGeocoder")
                            DispatchQueue.main.async {
                                completion(address)
                            }
                        } else {
                            let fallback = self.formatCoordinates(latitude, longitude)
                            DispatchQueue.main.async {
                                completion(fallback)
                            }
                        }
                    } catch {
                        log("Geocoding error: \(error.localizedDescription)", level: .warn, component: "ReverseGeocoder")
                        let fallback = self.formatCoordinates(latitude, longitude)
                        DispatchQueue.main.async {
                            completion(fallback)
                        }
                    }
                }
            } else {
                let fallback = self.formatCoordinates(latitude, longitude)
                DispatchQueue.main.async {
                    completion(fallback)
                }
            }
        }
    }

    /// Synchronous version - returns cached address or coordinate string immediately
    /// Use this when you can't wait for async geocoding
    func addressSync(for latitude: Double, longitude: Double) -> String {
        if let cached = findCached(lat: latitude, lon: longitude) {
            return cached
        }
        return formatCoordinates(latitude, longitude)
    }

    // MARK: - Private Methods

    private func findCached(lat: Double, lon: Double) -> String? {
        let now = Date()

        for entry in cache {
            // Check if not expired
            guard now.timeIntervalSince(entry.timestamp) < cacheExpiry else {
                continue
            }

            // Check if within radius
            let distance = haversineDistance(
                lat1: lat, lon1: lon,
                lat2: entry.latitude, lon2: entry.longitude
            )

            if distance < cacheRadius {
                return entry.address
            }
        }

        return nil
    }

    private func addToCache(address: String, lat: Double, lon: Double) {
        let entry = CachedAddress(
            address: address,
            timestamp: Date(),
            latitude: lat,
            longitude: lon
        )

        cache.append(entry)

        // Prune old entries if cache is too large
        if cache.count > maxCacheSize {
            // Remove oldest entries
            cache = Array(cache.suffix(maxCacheSize / 2))
        }
    }

    private func formatMapItem(_ mapItem: MKMapItem) -> String {
        // In macOS 26, use the new address property with shortAddress for concise display
        if let address = mapItem.address {
            // Use shortAddress for concise location display (e.g., "123 Main St" or "Downtown")
            if let short = address.shortAddress, !short.isEmpty {
                return short
            }
            // Fall back to full address if short is not available
            let full = address.fullAddress
            if !full.isEmpty {
                // Take just the first line for brevity
                let firstLine = full.components(separatedBy: "\n").first ?? full
                return firstLine
            }
        }

        // Fallback: use name if available
        if let name = mapItem.name, !name.isEmpty {
            return name
        }

        // Last resort: use coordinates
        return formatCoordinates(mapItem.location.coordinate.latitude,
                                mapItem.location.coordinate.longitude)
    }

    private func formatCoordinates(_ lat: Double, _ lon: Double) -> String {
        return String(format: "%.4f, %.4f", lat, lon)
    }

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0  // Earth radius in meters
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi/2) * sin(dPhi/2) +
                cos(phi1) * cos(phi2) *
                sin(dLambda/2) * sin(dLambda/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }
}
