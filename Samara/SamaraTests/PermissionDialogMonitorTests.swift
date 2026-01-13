import XCTest

final class PermissionDialogMonitorTests: SamaraTestCase {

    func testMonitorDoesNotNotifyWhenUnlocked() {
        let expectation = expectation(description: "no notify")
        expectation.isInverted = true

        let monitor = PermissionDialogMonitor(sendMessage: { _ in
            expectation.fulfill()
        })

        monitor.startMonitoring()
        wait(for: [expectation], timeout: 0.5)
        monitor.stopMonitoring()
    }
}
