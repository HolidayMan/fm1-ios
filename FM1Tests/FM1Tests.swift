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
    func testNativeCatalogueReleasesMatchTheLinkedEngineRegistry() {
        let entries=CatalogFirmware.bundled
        XCTAssertFalse(entries.isEmpty)
        let required:Set<String>=["sloop","official-open","felucca","x0x","melodee"]
        XCTAssertTrue(required.isSubset(of:Set(entries.map(\.id))))
        XCTAssertTrue(entries.allSatisfy {$0.nativeEngineName != nil},"Every offered release must match an engine in the actual linked archive")
        XCTAssertEqual(CatalogFirmware.available.map(\.id),entries.map(\.id))
        XCTAssertTrue(entries.first {$0.id == "official-open"}?.nativeEngineName?.contains("Preview") == true)
        XCTAssertFalse(entries.contains {$0.id == "stock"})
        for entry in entries {
            let altered=(entry.sha256.first == "0" ? "1" : "0")+String(entry.sha256.dropFirst())
            XCTAssertNil(NativeFirmwareSupport.name(forSHA256:altered),"A different binary must never be offered as an included instrument")
        }
    }
    func testSkiffLicenseLinksHaveBundledContentsWhenOffered()throws {
        guard CatalogFirmware.available.contains(where:{$0.id == "skiff"}) else{return}
        for name in ["NOTICE-native-skiff","LICENSE-native-skiff","THIRD-PARTY-native-skiff"] {
            let url=try XCTUnwrap(Bundle.main.url(forResource:name,withExtension:nil))
            XCTAssertFalse(try String(contentsOf:url).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
    }
    func testCommunityInstrumentsAreLinkedAndHaveBundledAttribution()throws {
        let expected:Set<UInt32>=Set(11...16)
        let entries=CatalogFirmware.bundled.filter {entry in
            let bytes=Array(entry.sha256.utf8)
            return bytes.withUnsafeBufferPointer {expected.contains(instrument_native_kind_for_sha256($0.baseAddress,$0.count))}
        }
        XCTAssertEqual(entries.count,expected.count,"All six curated community engines must actually be linked")
        XCTAssertTrue(entries.contains {$0.name == "CoralFlower"})
        XCTAssertTrue(entries.contains {$0.name == "JIANT FM"})
        XCTAssertTrue(entries.allSatisfy {$0.summary?.isEmpty == false},"New instruments explain their musical purpose")
        for name in ["NOTICE-native-community","LICENSE-native-community","THIRD-PARTY-native-community"] {
            let url=try XCTUnwrap(Bundle.main.url(forResource:name,withExtension:nil))
            XCTAssertFalse(try String(contentsOf:url).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
    }
    func testCatalogHasUniquePinnedSecureReleases() {
        let entries=CatalogFirmware.bundled
        XCTAssertEqual(Set(entries.map(\.id)).count,entries.count)
        for entry in entries {
            XCTAssertEqual(URL(string:entry.url)?.scheme,"https")
            XCTAssertEqual(URL(string:entry.source)?.scheme,"https")
            XCTAssertEqual(entry.sha256.count,64)
            XCTAssertTrue(entry.sha256.allSatisfy {"0123456789abcdef".contains($0)})
            XCTAssertTrue((960...4*1024*1024).contains(entry.size))
            XCTAssertFalse(entry.downloadSize.isEmpty)
            XCTAssertThrowsError(try entry.validate(Data(repeating:0,count:entry.size)))
        }
    }
}
