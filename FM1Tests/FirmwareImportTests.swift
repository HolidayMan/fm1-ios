#if FM1_RESEARCH
import XCTest
import SwiftUI
@testable import FM1

final class FirmwareImportTests: XCTestCase {
    @MainActor func testReimportKeepsExistingFileAndSaveIdentity() throws {
        let source=Instrument()
        guard let firmware=source.firmwares.first(where:{$0.name == "Stock-V15"}) else {throw XCTSkip("Requires the locally installed stock fixture; never downloads")}
        let original=try Data(contentsOf:firmware.url)
        let sourceSave=source.directory.appendingPathComponent(firmware.id).appendingPathExtension("flash")
        let rawSnapshot=try? Data(contentsOf:sourceSave)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let suite="FirmwareImportTests.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        let package=directory.appendingPathComponent(firmware.id).appendingPathExtension("fwsc")
        try original.write(to:package)
        let saveURL=directory.appendingPathComponent(firmware.id).appendingPathExtension("flash")
        if let rawSnapshot {try rawSnapshot.write(to:saveURL)}
        preferences.set(firmware.id,forKey:FirmwareSelection.preferenceKey)
        let model=Instrument(directory:directory,preferences:preferences)
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else {throw XCTSkip("Requires a foreground hosted window scene")}
        let idleTimerWasDisabled=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        let window=UIWindow(windowScene:scene)
        window.frame=scene.coordinateSpace.bounds
        window.rootViewController=UIHostingController(rootView:InstrumentView(instrument:model))
        window.makeKeyAndVisible()
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-renamed-identical-stock.fwsc")
        defer {
            model.pause()
            let paused=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.busy && !model.running},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[paused],timeout:25),.completed)
            window.isHidden=true;window.rootViewController=nil
            UIApplication.shared.isIdleTimerDisabled=idleTimerWasDisabled
            preferences.removePersistentDomain(forName:suite)
            try? FileManager.default.removeItem(at:temp)
            try? FileManager.default.removeItem(at:directory)
        }
        let before=Set(model.firmwares.map(\.id))
        try original.write(to:temp,options:.atomic)
        model.importFirmware(temp,removeAfterImport:true)
        let complete=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !model.busy },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[complete],timeout:65),.completed,"Reimport must finish through the real universal engine")
        XCTAssertNil(model.message)
        XCTAssertTrue(model.running,"Reimport must actually start the selected firmware")
        XCTAssertEqual(model.executionMode,.wasm)
        XCTAssertNotNil(model.experimentalWebView?.window,"The real WASM engine must have its native presentation attached")
        XCTAssertEqual(Set(model.firmwares.map(\.id)),before)
        XCTAssertEqual(model.selected?.id,firmware.id)
        if let rawSnapshot {
            XCTAssertEqual(try Data(contentsOf:saveURL),rawSnapshot,"Universal reimport must preserve the original raw flash branch")
        } else {XCTAssertFalse(FileManager.default.fileExists(atPath:saveURL.path))}
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.path))
    }
}

#endif
