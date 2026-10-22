import XCTest
@testable import FM1

final class FirmwareSelectionTests: XCTestCase {
    private func firmware(_ name: String, digest: String = "12345678") -> Firmware {
        let id = name + " · " + digest
        return Firmware(id: id, name: name, url: URL(fileURLWithPath: "/unused/\(id).fwsc"))
    }
    func testLastChoiceWinsAndMissingChoiceDefaultsToCurrentSloop() {
        let stock = firmware("Stock-V15"), older = firmware("SLOOP-2.6.0"), current = firmware("SLOOP-2.7.1")
        let library = [older, stock, current]
        XCTAssertEqual(FirmwareSelection.preferred(in: library, lastID: stock.id), stock)
        XCTAssertEqual(FirmwareSelection.preferred(in: library, lastID: nil), current)
        XCTAssertEqual(FirmwareSelection.preferred(in: library, lastID: "deleted"), current)
    }
    func testFallbackOnlySelectsSloopAndEmptyLibraryStaysEmpty() {
        let older = firmware("sloop-2.6.0"), newer = firmware("SLOOP-2.10.0")
        XCTAssertEqual(FirmwareSelection.preferred(in: [older,newer], lastID: nil), newer)
        XCTAssertNil(FirmwareSelection.preferred(in: [firmware("SLOOP Floyd FM-2.7.1"),firmware("Stock-V15")], lastID: nil))
        XCTAssertNil(FirmwareSelection.preferred(in: [], lastID: "missing"))
    }
    @MainActor func testLaunchRestoresChoicePausedWithoutLoadingOrDownloading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "FirmwareSelectionTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {try? FileManager.default.removeItem(at: directory);preferences.removePersistentDomain(forName: suite)}
        let stock = firmware("Stock-V15"), sloop = firmware("SLOOP-2.7.1")
        // Deliberately invalid bytes: a paused selection must not boot/import them.
        for fw in [stock, sloop] {try Data([0]).write(to: directory.appendingPathComponent(fw.id).appendingPathExtension("fwsc"))}
        let initial = Instrument(directory: directory, preferences: preferences)
        #if FM1_RESEARCH
        XCTAssertEqual(initial.selected?.id, sloop.id)
        #else
        XCTAssertNil(initial.selected,"Store startup does not offer invalid/unsupported package bytes")
        #endif
        XCTAssertFalse(initial.running);XCTAssertFalse(initial.busy);XCTAssertNil(initial.message)
        preferences.set(stock.id, forKey: FirmwareSelection.preferenceKey)
        let relaunched = Instrument(directory: directory, preferences: preferences)
        #if FM1_RESEARCH
        XCTAssertEqual(relaunched.selected?.id, stock.id)
        #else
        XCTAssertNil(relaunched.selected,"Remembered names cannot bypass the exact native registry")
        XCTAssertEqual(preferences.string(forKey:FirmwareSelection.preferenceKey),stock.id)
        #endif
        XCTAssertFalse(relaunched.running);XCTAssertNil(relaunched.screen)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }
}
