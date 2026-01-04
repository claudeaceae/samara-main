import XCTest

final class TaskLockTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any existing lock before each test
        TaskLock.release()
    }

    override func tearDown() {
        // Clean up after each test
        TaskLock.release()
        super.tearDown()
    }

    // MARK: - Basic Lock Tests

    func testAcquireLock() {
        // Should successfully acquire lock when none exists
        let acquired = TaskLock.acquire(task: "test")
        XCTAssertTrue(acquired, "Should acquire lock when none exists")
        XCTAssertTrue(TaskLock.isLocked(), "Lock should be held after acquisition")
    }

    func testAcquireLockTwiceFails() {
        // First acquisition should succeed
        let first = TaskLock.acquire(task: "test1")
        XCTAssertTrue(first)

        // Second acquisition should fail
        let second = TaskLock.acquire(task: "test2")
        XCTAssertFalse(second, "Should not acquire lock when one already exists")
    }

    func testReleaseLock() {
        TaskLock.acquire(task: "test")
        XCTAssertTrue(TaskLock.isLocked())

        TaskLock.release()
        XCTAssertFalse(TaskLock.isLocked(), "Lock should not be held after release")
    }

    func testReleaseNonexistentLockDoesNotCrash() {
        // Should not crash when releasing a lock that doesn't exist
        XCTAssertFalse(TaskLock.isLocked())
        TaskLock.release()  // Should not crash
        XCTAssertFalse(TaskLock.isLocked())
    }

    // MARK: - Task Info Tests

    func testCurrentTaskInfo() {
        TaskLock.acquire(task: "wake", chat: "test-chat-123")

        let info = TaskLock.currentTask()
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.task, "wake")
        XCTAssertEqual(info?.chat, "test-chat-123")
        XCTAssertEqual(info?.pid, ProcessInfo.processInfo.processIdentifier)
    }

    func testCurrentTaskNilWhenUnlocked() {
        let info = TaskLock.currentTask()
        XCTAssertNil(info, "Should return nil when no lock is held")
    }

    func testTaskDescription() {
        TaskLock.acquire(task: "wake")
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "a wake cycle")
    }

    func testTaskDescriptionDream() {
        TaskLock.acquire(task: "dream")
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "a dream cycle")
    }

    func testTaskDescriptionMessage() {
        TaskLock.acquire(task: "message")
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "another conversation")
    }

    func testTaskDescriptionUnknown() {
        TaskLock.acquire(task: "custom-task")
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "custom-task")
    }

    // MARK: - Stale Lock Tests

    func testNotStaleWhenFresh() {
        TaskLock.acquire(task: "test")
        XCTAssertFalse(TaskLock.isStale(), "Fresh lock should not be stale")
    }

    func testNotStaleWithCurrentProcess() {
        // Lock from current process should not be stale
        TaskLock.acquire(task: "test")

        // Since we're the process that created it, it shouldn't be stale
        XCTAssertFalse(TaskLock.isStale())
    }

    // MARK: - Acquire After Release Tests

    func testAcquireAfterRelease() {
        TaskLock.acquire(task: "test1")
        TaskLock.release()

        let acquired = TaskLock.acquire(task: "test2")
        XCTAssertTrue(acquired, "Should be able to acquire lock after release")

        let info = TaskLock.currentTask()
        XCTAssertEqual(info?.task, "test2")
    }
}
