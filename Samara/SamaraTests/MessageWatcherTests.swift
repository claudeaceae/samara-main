import XCTest

final class MessageWatcherTests: SamaraTestCase {
    func testCheckNowProcessesNewMessagesOnce() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        var receivedRowIds: [Int64] = []
        let watcher = MessageWatcher(
            store: store,
            onNewMessage: { message in
                receivedRowIds.append(message.rowId)
            },
            initialRowId: 0,
            watchPath: fixture.dbURL.path,
            enableFileWatcher: false,
            enablePolling: false
        )

        watcher.checkNow()

        XCTAssertEqual(receivedRowIds, [
            fixture.directMessageRowId,
            fixture.groupMessageRowId,
            fixture.reactionRowId,
            fixture.attachmentMessageRowId
        ])

        watcher.checkNow()
        XCTAssertEqual(receivedRowIds.count, 4)
    }

    func testConcurrentCheckNowDoesNotDuplicate() throws {
        let fixture = try MessageStoreFixture()
        defer { fixture.cleanup() }

        let store = try fixture.makeStore()
        defer { store.close() }

        var receivedRowIds: [Int64] = []
        let lock = NSLock()

        let watcher = MessageWatcher(
            store: store,
            onNewMessage: { message in
                lock.lock()
                receivedRowIds.append(message.rowId)
                lock.unlock()
            },
            initialRowId: 0,
            watchPath: fixture.dbURL.path,
            enableFileWatcher: false,
            enablePolling: false
        )

        let group = DispatchGroup()
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                watcher.checkNow()
                group.leave()
            }
            group.enter()
            DispatchQueue.main.async {
                watcher.checkNow()
                group.leave()
            }
        }
        group.wait()

        let uniqueRowIds = Set(receivedRowIds)
        XCTAssertEqual(uniqueRowIds.count, receivedRowIds.count, "No duplicates should be present")
    }
}
