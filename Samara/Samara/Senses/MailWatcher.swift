import Foundation

/// Watches for new emails from target senders and triggers a callback
final class MailWatcher {
    private let store: MailStore
    private let onNewEmail: (Email) -> Void

    /// Poll interval for checking mail
    private let pollInterval: TimeInterval

    /// IDs of emails we've already seen
    private var seenEmailIds: Set<String> = []

    /// Lock for thread safety
    private let lock = NSLock()

    /// Polling thread
    private var watchThread: Thread?

    /// Flag to stop watching
    private var shouldStop = false

    /// Path to persist seen email IDs
    private let seenIdsPath: String

    init(
        store: MailStore,
        pollInterval: TimeInterval = 30,
        onNewEmail: @escaping (Email) -> Void
    ) {
        self.store = store
        self.pollInterval = pollInterval
        self.onNewEmail = onNewEmail

        self.seenIdsPath = MindPaths.mindPath("mail-seen-ids.json")

        // Load previously seen IDs
        loadSeenIds()
    }

    /// Starts watching for new emails
    func start() {
        guard watchThread == nil else { return }

        shouldStop = false
        log("[MailWatcher] Starting with poll interval: \(Int(pollInterval))s")

        // Do initial check
        checkForNewEmails()

        // Start polling thread
        let watcher = self
        let interval = pollInterval
        let thread = Thread { [weak self] in
            log("[MailWatcher] Poll thread running")
            while let self = self, !self.shouldStop {
                Thread.sleep(forTimeInterval: interval)
                if self.shouldStop { break }
                autoreleasepool {
                    watcher.checkForNewEmails()
                }
            }
        }
        thread.qualityOfService = .utility
        thread.start()
        watchThread = thread
        log("[MailWatcher] Poll thread started")
    }

    /// Stop watching for emails
    func stop() {
        shouldStop = true
        watchThread?.cancel()
        watchThread = nil
        log("[MailWatcher] Poll thread stopped")
    }

    /// Check for new emails from target senders
    private func checkForNewEmails() {
        log("[MailWatcher] Polling for new emails...")
        do {
            // Fetch unread emails
            let emails = try store.fetchUnreadEmails()

            lock.lock()
            let currentSeenIds = seenEmailIds
            lock.unlock()

            var newEmails: [Email] = []

            for email in emails {
                // Skip if we've already seen this email
                if currentSeenIds.contains(email.id) {
                    continue
                }

                // Skip if not from target sender
                if !store.isFromTarget(email) {
                    continue
                }

                newEmails.append(email)
            }

            if !newEmails.isEmpty {
                log("[MailWatcher] Found \(newEmails.count) new email(s) from target sender(s)")

                for email in newEmails {
                    log("[MailWatcher] New email from \(email.sender): \(email.subject)")

                    // Mark as seen
                    lock.lock()
                    seenEmailIds.insert(email.id)
                    lock.unlock()

                    // Trigger callback
                    onNewEmail(email)
                }

                // Persist seen IDs
                saveSeenIds()
            } else {
                log("[MailWatcher] No new emails from target senders (checked \(emails.count) unread)")
            }
        } catch {
            log("[MailWatcher] Error checking emails: \(error)")
        }
    }

    /// Mark an email as processed (in case it wasn't caught during regular check)
    func markAsSeen(_ emailId: String) {
        lock.lock()
        seenEmailIds.insert(emailId)
        lock.unlock()
        saveSeenIds()
    }

    // MARK: - Persistence

    private func loadSeenIds() {
        guard FileManager.default.fileExists(atPath: seenIdsPath) else { return }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: seenIdsPath))
            let ids = try JSONDecoder().decode([String].self, from: data)
            seenEmailIds = Set(ids)
            log("[MailWatcher] Loaded \(ids.count) seen email IDs")
        } catch {
            log("[MailWatcher] Failed to load seen IDs: \(error)")
        }
    }

    private func saveSeenIds() {
        lock.lock()
        let ids = Array(seenEmailIds)
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(ids)
            try data.write(to: URL(fileURLWithPath: seenIdsPath))
        } catch {
            log("[MailWatcher] Failed to save seen IDs: \(error)")
        }
    }

    /// Prune old seen IDs to prevent unbounded growth (call periodically)
    func pruneSeenIds(keepCount: Int = 1000) {
        lock.lock()
        if seenEmailIds.count > keepCount {
            // Just keep the most recent keepCount IDs
            // Since we don't track timestamps, we'll just randomly keep some
            let idsArray = Array(seenEmailIds)
            seenEmailIds = Set(idsArray.suffix(keepCount))
            log("[MailWatcher] Pruned seen IDs to \(seenEmailIds.count)")
        }
        lock.unlock()
        saveSeenIds()
    }
}
