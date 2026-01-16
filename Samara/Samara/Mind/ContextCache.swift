import Foundation

/// Thread-safe cache for context components with TTL-based expiration
actor ContextCache {

    // MARK: - Types

    /// Cached context entry with metadata
    struct CachedEntry {
        let content: String
        let loadedAt: Date
        let tokenEstimate: Int
        let source: String  // File path or identifier

        var age: TimeInterval {
            Date().timeIntervalSince(loadedAt)
        }
    }

    /// Cache statistics for monitoring
    struct CacheStats {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0

        var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0
        }
    }

    // MARK: - Properties

    /// Cache storage
    private var cache: [String: CachedEntry] = [:]

    /// Default TTL for cached entries (5 minutes)
    private let defaultTTL: TimeInterval

    /// Maximum entries before LRU eviction
    private let maxEntries: Int

    /// Cache statistics
    private var stats = CacheStats()

    /// File modification times for invalidation
    private var fileModTimes: [String: Date] = [:]

    // MARK: - Initialization

    init(defaultTTL: TimeInterval = 300, maxEntries: Int = 50) {
        self.defaultTTL = defaultTTL
        self.maxEntries = maxEntries

        log("ContextCache initialized with TTL=\(Int(defaultTTL))s, maxEntries=\(maxEntries)",
            level: .info, component: "ContextCache")
    }

    // MARK: - Public Methods

    /// Get cached content if available and not expired
    /// - Parameters:
    ///   - key: Cache key (e.g., "capabilities", "person_alice")
    ///   - maxAge: Maximum age in seconds (defaults to configured TTL)
    /// - Returns: Cached content if valid, nil otherwise
    func get(_ key: String, maxAge: TimeInterval? = nil) -> String? {
        let effectiveTTL = maxAge ?? defaultTTL

        guard let entry = cache[key] else {
            stats.misses += 1
            return nil
        }

        // Check expiration
        if entry.age > effectiveTTL {
            cache.removeValue(forKey: key)
            stats.misses += 1
            return nil
        }

        // Check if source file was modified
        if let source = entry.source.isEmpty ? nil : entry.source,
           hasFileChanged(source, since: entry.loadedAt) {
            cache.removeValue(forKey: key)
            stats.misses += 1
            log("Cache invalidated for '\(key)' - source file modified", level: .debug, component: "ContextCache")
            return nil
        }

        stats.hits += 1
        return entry.content
    }

    /// Store content in cache
    /// - Parameters:
    ///   - key: Cache key
    ///   - content: Content to cache
    ///   - tokens: Estimated token count
    ///   - source: Source file path (for invalidation tracking)
    func set(_ key: String, content: String, tokens: Int = 0, source: String = "") {
        // Enforce max entries
        if cache.count >= maxEntries && cache[key] == nil {
            evictOldest()
        }

        cache[key] = CachedEntry(
            content: content,
            loadedAt: Date(),
            tokenEstimate: tokens,
            source: source
        )

        // Track source file modification time
        if !source.isEmpty {
            trackFileModTime(source)
        }
    }

    /// Invalidate a specific cache entry
    /// - Parameter key: Cache key to invalidate
    func invalidate(_ key: String) {
        if cache.removeValue(forKey: key) != nil {
            stats.evictions += 1
            log("Invalidated cache key: \(key)", level: .debug, component: "ContextCache")
        }
    }

    /// Invalidate all entries matching a prefix
    /// - Parameter prefix: Key prefix to match (e.g., "person_" invalidates all person profiles)
    func invalidatePrefix(_ prefix: String) {
        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            stats.evictions += 1
        }

        if !keysToRemove.isEmpty {
            log("Invalidated \(keysToRemove.count) entries with prefix '\(prefix)'",
                level: .debug, component: "ContextCache")
        }
    }

    /// Invalidate all cached entries
    func invalidateAll() {
        let count = cache.count
        cache.removeAll()
        stats.evictions += count
        log("Invalidated all \(count) cache entries", level: .info, component: "ContextCache")
    }

    /// Get current cache statistics
    func getStats() -> CacheStats {
        return stats
    }

    /// Get total estimated tokens in cache
    func totalCachedTokens() -> Int {
        return cache.values.reduce(0) { $0 + $1.tokenEstimate }
    }

    /// Get number of cached entries
    func entryCount() -> Int {
        return cache.count
    }

    /// Clean up expired entries
    func cleanExpired() {
        let now = Date()
        let expiredKeys = cache.filter { now.timeIntervalSince($0.value.loadedAt) > defaultTTL }.map { $0.key }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
            stats.evictions += 1
        }

        if !expiredKeys.isEmpty {
            log("Cleaned \(expiredKeys.count) expired cache entries", level: .debug, component: "ContextCache")
        }
    }

    // MARK: - Private Methods

    /// Evict oldest entry to make room
    private func evictOldest() {
        guard let oldest = cache.min(by: { $0.value.loadedAt < $1.value.loadedAt }) else {
            return
        }

        cache.removeValue(forKey: oldest.key)
        stats.evictions += 1
        log("Evicted oldest cache entry: \(oldest.key)", level: .debug, component: "ContextCache")
    }

    /// Check if a file has been modified since a given date
    private func hasFileChanged(_ path: String, since date: Date) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false  // Can't determine, assume not changed
        }

        return modDate > date
    }

    /// Track the modification time of a source file
    private func trackFileModTime(_ path: String) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date {
            fileModTimes[path] = modDate
        }
    }
}

// MARK: - Cache Keys

extension ContextCache {
    /// Standard cache keys for context modules
    enum Key {
        static let identitySummary = "identity_summary"
        static let goalsActive = "goals_active"
        static let capabilitiesSummary = "capabilities_summary"
        static let decisionsRecent = "decisions_recent"
        static let learningsRecent = "learnings_recent"
        static let observationsRecent = "observations_recent"
        static let questionsRecent = "questions_recent"
        static let locationCurrent = "location_current"
        static let calendarToday = "calendar_today"
        static let episodeToday = "episode_today"
        static let coreContext = "core_context"

        static func person(_ name: String) -> String {
            return "person_\(name.lowercased())"
        }

        static func search(_ query: String) -> String {
            return "search_\(query.lowercased().prefix(50))"
        }
    }
}
