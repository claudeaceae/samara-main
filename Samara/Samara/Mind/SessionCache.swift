import Foundation

/// Thread-safe in-memory cache for session states with TTL
/// Reduces filesystem I/O for frequent session lookups
actor SessionCache {

    // MARK: - Types

    /// Cached session with timestamp for TTL validation
    private struct CachedEntry {
        let state: SessionManager.SessionState
        let cachedAt: Date

        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(cachedAt) < ttl
        }
    }

    /// Cache statistics for monitoring
    struct CacheStats {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
        var invalidations: Int = 0

        var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }
    }

    // MARK: - Properties

    /// In-memory cache: chatIdentifier -> cached entry
    private var cache: [String: CachedEntry] = [:]

    /// Time-to-live for cached entries
    private let ttl: TimeInterval

    /// Cache statistics
    private var stats = CacheStats()

    /// Maximum number of entries (prevents unbounded growth)
    private let maxEntries: Int

    // MARK: - Initialization

    /// Initialize session cache
    /// - Parameters:
    ///   - ttl: Time-to-live for cached entries (default: 45 seconds)
    ///   - maxEntries: Maximum number of cached entries (default: 100)
    init(ttl: TimeInterval = 45.0, maxEntries: Int = 100) {
        self.ttl = ttl
        self.maxEntries = maxEntries
        log("SessionCache initialized with TTL=\(Int(ttl))s, maxEntries=\(maxEntries)",
            level: .info, component: "SessionCache")
    }

    // MARK: - Public Interface

    /// Get a cached session state if valid
    /// - Parameter chatId: The chat identifier
    /// - Returns: Cached session state if present and not expired, nil otherwise
    func get(_ chatId: String) -> SessionManager.SessionState? {
        guard let cached = cache[chatId] else {
            stats.misses += 1
            return nil
        }

        if cached.isValid(ttl: ttl) {
            stats.hits += 1
            return cached.state
        }

        // Expired - remove from cache
        cache.removeValue(forKey: chatId)
        stats.evictions += 1
        stats.misses += 1
        return nil
    }

    /// Cache a session state
    /// - Parameters:
    ///   - chatId: The chat identifier
    ///   - state: The session state to cache
    func set(_ chatId: String, state: SessionManager.SessionState) {
        // Evict old entries if at capacity
        if cache.count >= maxEntries {
            evictOldestEntries()
        }

        cache[chatId] = CachedEntry(state: state, cachedAt: Date())
    }

    /// Invalidate a specific cache entry
    /// - Parameter chatId: The chat identifier to invalidate
    func invalidate(_ chatId: String) {
        if cache.removeValue(forKey: chatId) != nil {
            stats.invalidations += 1
        }
    }

    /// Invalidate all cache entries
    func invalidateAll() {
        let count = cache.count
        cache.removeAll()
        stats.invalidations += count
        log("Invalidated all \(count) cached sessions", level: .info, component: "SessionCache")
    }

    /// Get current cache statistics
    func getStats() -> CacheStats {
        return stats
    }

    /// Reset cache statistics
    func resetStats() {
        stats = CacheStats()
    }

    /// Get the number of cached entries
    var count: Int {
        cache.count
    }

    /// Check if cache contains a valid entry for a chat
    func contains(_ chatId: String) -> Bool {
        guard let cached = cache[chatId] else { return false }
        return cached.isValid(ttl: ttl)
    }

    // MARK: - Private Methods

    /// Evict oldest entries to make room
    private func evictOldestEntries() {
        // Remove expired entries first
        let now = Date()
        var expiredKeys: [String] = []
        for (key, entry) in cache where !entry.isValid(ttl: ttl) {
            expiredKeys.append(key)
        }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
            stats.evictions += 1
        }

        // If still at capacity, remove oldest entries
        if cache.count >= maxEntries {
            let sortedByAge = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
            let toRemove = max(1, cache.count - maxEntries + 1)

            for i in 0..<min(toRemove, sortedByAge.count) {
                cache.removeValue(forKey: sortedByAge[i].key)
                stats.evictions += 1
            }
        }
    }

    /// Clean up expired entries (call periodically)
    func cleanup() {
        var expiredCount = 0
        let keys = Array(cache.keys)

        for key in keys {
            if let entry = cache[key], !entry.isValid(ttl: ttl) {
                cache.removeValue(forKey: key)
                expiredCount += 1
                stats.evictions += 1
            }
        }

        if expiredCount > 0 {
            log("Cleaned up \(expiredCount) expired cache entries", level: .debug, component: "SessionCache")
        }
    }
}

// MARK: - SessionManager Integration

/// Extension to provide synchronous cache access for SessionManager
/// Since SessionManager uses NSLock, we provide a synchronous wrapper
extension SessionCache {

    /// Synchronously get a cached session (blocks calling thread)
    /// Use this only when you can't use async/await
    nonisolated func getSync(_ chatId: String) -> SessionManager.SessionState? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SessionManager.SessionState?

        Task {
            result = await self.get(chatId)
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    /// Synchronously cache a session state (blocks calling thread)
    nonisolated func setSync(_ chatId: String, state: SessionManager.SessionState) {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await self.set(chatId, state: state)
            semaphore.signal()
        }

        semaphore.wait()
    }

    /// Synchronously invalidate a cache entry (blocks calling thread)
    nonisolated func invalidateSync(_ chatId: String) {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await self.invalidate(chatId)
            semaphore.signal()
        }

        semaphore.wait()
    }
}
