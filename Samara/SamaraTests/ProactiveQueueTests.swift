import XCTest

final class ProactiveQueueTests: SamaraTestCase {

    private func makeBaseDir() -> String {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-proactive-queue-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.path
    }

    private func loadStats(baseDir: String) throws -> ProactiveQueue.DailyStats {
        let statsURL = URL(fileURLWithPath: baseDir)
            .appendingPathComponent("proactive-queue")
            .appendingPathComponent("stats.json")
        let data = try Data(contentsOf: statsURL)
        return try JSONDecoder().decode(ProactiveQueue.DailyStats.self, from: data)
    }

    func testEnqueueDropsWhenDailyLimitReached() throws {
        let baseDir = makeBaseDir()
        let queue = ProactiveQueue(baseDir: baseDir)
        var config = queue.config
        config.maxMessagesPerDay = 0
        queue.updateConfig(config)

        let id = queue.enqueue(content: "Hello")
        XCTAssertNil(id)

        let stats = try loadStats(baseDir: baseDir)
        XCTAssertEqual(stats.messagesDropped, 1)
    }

    func testDequeueAllowsTimeSensitiveDuringQuietHours() {
        let baseDir = makeBaseDir()
        let queue = ProactiveQueue(baseDir: baseDir)
        var config = queue.config
        config.quietHoursStart = 0
        config.quietHoursEnd = 23
        config.minIntervalSeconds = 3600
        queue.updateConfig(config)

        _ = queue.enqueue(content: "Normal", priority: .medium)
        _ = queue.enqueue(content: "Urgent", priority: .timeSensitive)

        let next = queue.dequeue()
        XCTAssertEqual(next?.priority, .timeSensitive)
    }

    func testDequeueRespectsMinInterval() {
        let baseDir = makeBaseDir()
        let queue = ProactiveQueue(baseDir: baseDir)
        var config = queue.config
        let hour = Calendar.current.component(.hour, from: Date())
        config.quietHoursStart = (hour + 1) % 24
        config.quietHoursEnd = hour
        config.minIntervalSeconds = 3600
        config.priorityBoostMultiplier = 1.0
        queue.updateConfig(config)

        _ = queue.enqueue(content: "Later", priority: .medium)
        queue.markSent(messageId: "sent")

        XCTAssertNil(queue.dequeue())
        XCTAssertNotNil(queue.getStatus().nextReady)
    }

    func testExpiredMessageIsRemovedOnDequeue() throws {
        let baseDir = makeBaseDir()
        let queue = ProactiveQueue(baseDir: baseDir)
        var config = queue.config
        let hour = Calendar.current.component(.hour, from: Date())
        config.quietHoursStart = (hour + 1) % 24
        config.quietHoursEnd = hour
        config.minIntervalSeconds = 0
        queue.updateConfig(config)

        _ = queue.enqueue(content: "Expired", priority: .low, expiresIn: -1)

        XCTAssertNil(queue.dequeue())
        XCTAssertTrue(queue.getPending().isEmpty)

        let stats = try loadStats(baseDir: baseDir)
        XCTAssertEqual(stats.messagesExpired, 1)
    }
}
