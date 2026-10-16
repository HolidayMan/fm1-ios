import XCTest
@testable import FM1

final class FirmwareImportTests: XCTestCase {
    @MainActor func testReimportKeepsExistingFileAndSaveIdentity() throws {
        let model=Instrument()
        guard let firmware=model.firmwares.first(where:{$0.name == "Stock-V15"}) else {throw XCTSkip("Requires the locally installed stock fixture")}
        let before=Set(model.firmwares.map(\.id))
        let original=try Data(contentsOf:firmware.url)
        let saveURL=model.directory.appendingPathComponent(firmware.id).appendingPathExtension("flash")
        let savedState=try? Data(contentsOf:saveURL)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("renamed-identical-stock.fwsc")
        try original.write(to:temp,options:.atomic)
        defer {model.pause();try? FileManager.default.removeItem(at:temp)}
        model.importFirmware(temp,removeAfterImport:true)
        let complete=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !model.busy && model.selected != nil },object:nil)
        guard XCTWaiter.wait(for:[complete],timeout:20) == .completed else {XCTFail("Reimport did not finish");return}
        XCTAssertEqual(Set(model.firmwares.map(\.id)),before)
        XCTAssertEqual(model.selected?.id,firmware.id)
        if let savedState {XCTAssertEqual(try Data(contentsOf:saveURL),savedState,"Reimport must preserve the existing save at the same identity")}
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.path))
    }
}
