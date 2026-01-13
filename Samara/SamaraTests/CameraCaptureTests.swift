import XCTest

final class CameraCaptureTests: SamaraTestCase {

    func testCaptureErrorDescriptions() {
        XCTAssertEqual(CameraCapture.CaptureError.noCamera.errorDescription, "No camera device found")
        XCTAssertEqual(CameraCapture.CaptureError.accessDenied.errorDescription, "Camera access denied")
        XCTAssertEqual(CameraCapture.CaptureError.setupFailed("bad").errorDescription, "Camera setup failed: bad")
        XCTAssertEqual(CameraCapture.CaptureError.captureFailed("oops").errorDescription, "Photo capture failed: oops")
    }
}
