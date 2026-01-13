import XCTest

final class NoteWatcherTests: SamaraTestCase {

    func testCheckNoteReturnsPlainText() {
        let watcher = NoteWatcher(
            watchedNotes: ["Test Note"],
            noteReader: { _ in
                return ("<b>Hello</b>&nbsp;World", "Hello World")
            },
            onNoteChanged: { _ in }
        )

        let update = watcher.checkNote(named: "Test Note")
        XCTAssertNotNil(update)
        XCTAssertEqual(update?.plainTextContent, "Hello World")
        XCTAssertEqual(update?.noteName, "Test Note")
    }

    func testStartDetectsContentChange() {
        let expectation = expectation(description: "note change")
        var callCount = 0

        let watcher = NoteWatcher(
            watchedNotes: ["Change Note"],
            pollInterval: 0.1,
            noteReader: { _ in
                callCount += 1
                if callCount < 2 {
                    return ("<p>Old content</p>", "Old content")
                }
                return ("<p>Updated content!</p>", "Updated content!")
            },
            onNoteChanged: { update in
                XCTAssertEqual(update.plainTextContent, "Updated content!")
                expectation.fulfill()
            }
        )

        watcher.start()
        wait(for: [expectation], timeout: 1.0)
        watcher.stop()
    }
}
