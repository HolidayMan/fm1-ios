import XCTest
@testable import FM1
final class FM1Tests: XCTestCase {
    func testEmptyLibraryDoesNotPretendToRunFirmware() {
        let model=Instrument()
        XCTAssertFalse(model.running)
        XCTAssertNil(model.screen)
        XCTAssertNil(model.selected)
    }
    func testMasterClampsHardwareRange() {
        let model=Instrument()
        model.master(3);XCTAssertEqual(model.volume,1)
        model.master(-3);XCTAssertEqual(model.volume,0)
    }
}
