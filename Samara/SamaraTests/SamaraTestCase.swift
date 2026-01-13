import XCTest

class SamaraTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestEnvironment.installIfNeeded()
    }
}
