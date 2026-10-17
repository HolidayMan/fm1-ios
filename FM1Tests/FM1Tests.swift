import XCTest
@testable import FM1
final class FM1Tests: XCTestCase {
    func testEmptyLibraryDoesNotPretendToRunFirmware() {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=Instrument(directory:directory)
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

final class FirmwareCatalogTests: XCTestCase {
    func testCatalogHasUniquePinnedSecureReleases() {
        let entries = CatalogFirmware.bundled
        XCTAssertEqual(entries.count, 53)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertTrue(entries.contains {$0.id == "stock"})
        XCTAssertTrue(entries.contains {$0.id == "felucca"})
        for entry in entries {
            XCTAssertEqual(URL(string:entry.url)?.scheme,"https")
            XCTAssertEqual(entry.sha256.count,64)
            XCTAssertTrue((960...4*1024*1024).contains(entry.size))
            XCTAssertThrowsError(try entry.validate(Data(repeating:0,count:entry.size)))
        }
    }
}
