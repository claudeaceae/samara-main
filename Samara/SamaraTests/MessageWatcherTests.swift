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
}
