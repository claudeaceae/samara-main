import XCTest

final class TaskLockTests: SamaraTestCase {

    override func setUp() {
        super.setUp()
        clearLocks()
    }

    override func tearDown() {
        clearLocks()
        super.tearDown()
    }

    private func clearLocks() {
        for lock in TaskLock.activeLocks() {
            TaskLock.release(scope: lock.scope)
        }
    }

    // MARK: - Basic Lock Tests

    func testAcquireLock() {
        // Should successfully acquire lock when none exists
        let scope = LockScope.systemTask(name: "test")
        let acquired = TaskLock.acquire(scope: scope, task: "test")
        XCTAssertTrue(acquired, "Should acquire lock when none exists")
        XCTAssertTrue(TaskLock.isLocked(scope: scope), "Lock should be held after acquisition")
    }

    func testAcquireLockTwiceFails() {
        let scope = LockScope.systemTask(name: "test")

        // First acquisition should succeed
        let first = TaskLock.acquire(scope: scope, task: "test")
        XCTAssertTrue(first)

        // Second acquisition should fail
        let second = TaskLock.acquire(scope: scope, task: "test")
        XCTAssertFalse(second, "Should not acquire lock when one already exists for the same scope")
    }

    func testReleaseLock() {
        let scope = LockScope.systemTask(name: "test")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "test"))
        XCTAssertTrue(TaskLock.isLocked(scope: scope))

        TaskLock.release(scope: scope)
        XCTAssertFalse(TaskLock.isLocked(scope: scope), "Lock should not be held after release")
    }

    func testReleaseNonexistentLockDoesNotCrash() {
        // Should not crash when releasing a lock that doesn't exist
        let scope = LockScope.systemTask(name: "test")
        XCTAssertFalse(TaskLock.isLocked(scope: scope))
        TaskLock.release(scope: scope)  // Should not crash
        XCTAssertFalse(TaskLock.isLocked(scope: scope))
    }

    // MARK: - Task Info Tests

    func testCurrentTaskInfo() {
        let scope = LockScope.conversation(chatIdentifier: "test-chat-123")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "wake"))

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
        let scope = LockScope.systemTask(name: "wake")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "wake"))
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "a wake cycle")
    }

    func testTaskDescriptionDream() {
        let scope = LockScope.systemTask(name: "dream")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "dream"))
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "a dream cycle")
    }

    func testTaskDescriptionMessage() {
        let scope = LockScope.systemTask(name: "message")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "message"))
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "another conversation")
    }

    func testTaskDescriptionUnknown() {
        let scope = LockScope.systemTask(name: "custom-task")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "custom-task"))
        let desc = TaskLock.taskDescription()
        XCTAssertEqual(desc, "custom-task")
    }

    // MARK: - Stale Lock Tests

    func testNotStaleWhenFresh() {
        let scope = LockScope.systemTask(name: "test")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "test"))
        XCTAssertFalse(TaskLock.isStale(), "Fresh lock should not be stale")
    }

    func testNotStaleWithCurrentProcess() {
        // Lock from current process should not be stale
        let scope = LockScope.systemTask(name: "test")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "test"))

        // Since we're the process that created it, it shouldn't be stale
        XCTAssertFalse(TaskLock.isStale())
    }

    // MARK: - Acquire After Release Tests

    func testAcquireAfterRelease() {
        let scope = LockScope.systemTask(name: "test1")
        XCTAssertTrue(TaskLock.acquire(scope: scope, task: "test1"))
        TaskLock.release(scope: scope)

        let nextScope = LockScope.systemTask(name: "test2")
        let acquired = TaskLock.acquire(scope: nextScope, task: "test2")
        XCTAssertTrue(acquired, "Should be able to acquire lock after release")

        let info = TaskLock.currentTask()
        XCTAssertEqual(info?.task, "test2")
    }
}
