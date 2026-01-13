import XCTest

final class ReverseGeocoderTests: SamaraTestCase {

    func testAddressSyncFormatsCoordinates() {
        let address = ReverseGeocoder.shared.addressSync(for: 40.7128, longitude: -74.0060)
        XCTAssertEqual(address, "40.7128, -74.0060")
    }
}
