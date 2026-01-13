import XCTest

final class SessionCacheTests: SamaraTestCase {

    private func makeState(id: String, chat: String) -> SessionManager.SessionState {
        SessionManager.SessionState(
            sessionId: id,
            chatIdentifier: chat,
            lastResponseRowId: nil,
            lastResponseTime: Date(),
            lastReadTime: nil
        )
    }

    func testCacheHitAndExpires() async {
        let cache = SessionCache(ttl: 0.01, maxEntries: 5)
        let state = makeState(id: "s1", chat: "chat1")

        await cache.set("chat1", state: state)
        let first = await cache.get("chat1")
        XCTAssertNotNil(first)

        try? await Task.sleep(nanoseconds: 20_000_000)
        let expired = await cache.get("chat1")
        XCTAssertNil(expired)

        let stats = await cache.getStats()
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertGreaterThanOrEqual(stats.evictions, 1)
    }

    func testEvictsOldestWhenAtCapacity() async {
        let cache = SessionCache(ttl: 60.0, maxEntries: 1)
        let first = makeState(id: "s1", chat: "chat1")
        let second = makeState(id: "s2", chat: "chat2")

        await cache.set("chat1", state: first)
        await cache.set("chat2", state: second)

        let firstResult = await cache.get("chat1")
        let secondResult = await cache.get("chat2")
        XCTAssertNil(firstResult)
        XCTAssertNotNil(secondResult)
    }
}
