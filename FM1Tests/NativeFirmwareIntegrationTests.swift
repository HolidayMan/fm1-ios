import XCTest
import UIKit
@testable import FM1

/// Uses installed local packages, with every writable file in a temporary library.
@MainActor final class NativeFirmwareIntegrationTests:XCTestCase {
    func testCuratedNativeRoutesReopenTheirOwnSaveFormats()throws {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let sources=[documents.appendingPathComponent("Native16Packages"),documents.appendingPathComponent("Native13Packages"),documents.appendingPathComponent("Firmwares")]
        var packages:[UInt32:Data]=[:]
        for source in sources {
            for url in (try? FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "fwsc" {
                let bytes=try Data(contentsOf:url)
                let kind=bytes.withUnsafeBytes {instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,bytes.count)}
                if kind != 0 {packages[kind]=bytes}
            }
        }
        guard (2...9).allSatisfy({packages[UInt32($0)] != nil}) else {throw XCTSkip("Requires all eight pinned local packages; never downloads")}
        let idle=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        defer {UIApplication.shared.isIdleTimerDisabled=idle}
        for kind:UInt32 in 2...9 {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let id="native-\(kind)",suite="NativeRoutingTests.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
            let package=directory.appendingPathComponent(id).appendingPathExtension("fwsc")
            try XCTUnwrap(packages[kind]).write(to:package)
            // An old hardware-emulator save must not be read or overwritten by Preview.
            let legacy=directory.appendingPathComponent(id).appendingPathExtension("flash")
            let sentinel=Data(repeating:0xa5,count:1<<20)
            if kind == 6 {try sentinel.write(to:legacy)}
            let model=Instrument(directory:directory,preferences:preferences,nativeOnly:true)
            defer {model.pause();settle(model,running:false);preferences.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
            let scanned=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.firmwares.isEmpty},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[scanned],timeout:20),.completed)
            model.load(try XCTUnwrap(model.firmwares.first));settle(model,running:true)
            XCTAssertNil(model.message)
            XCTAssertEqual(model.executionMode,.native)
            XCTAssertEqual(model.nativeBackendName,NativeFirmwareSupport.name(forKind:kind))
            XCTAssertFalse(model.supportsExperimentalWASM)
            XCTAssertFalse(model.supportsClockControl)
            model.pause();settle(model,running:false)
            let saved=directory.appendingPathComponent(id).appendingPathExtension(kind == 6 ? "preview.flash" : "flash")
            let before=try Data(contentsOf:saved)
            XCTAssertEqual(before.count,kind == 6 ? 536576 : 1<<20)
            model.load(try XCTUnwrap(model.selected));settle(model,running:true)
            model.pause();settle(model,running:false)
            XCTAssertEqual(try Data(contentsOf:saved),before,"Reload must restore its complete native save")
            if kind == 6 {XCTAssertEqual(try Data(contentsOf:legacy),sentinel)}
        }
    }
    private func settle(_ model:Instrument,running:Bool,file:StaticString=#filePath,line:UInt=#line) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.busy && model.running == running},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:20),.completed,"\(model.status): \(model.message ?? "no error")",file:file,line:line)
    }
}
