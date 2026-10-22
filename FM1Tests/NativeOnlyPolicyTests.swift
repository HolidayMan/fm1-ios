import XCTest
import UIKit
@testable import FM1

@MainActor final class NativeOnlyPolicyTests:XCTestCase {
    func testUnsupportedFileIsHiddenAndRejectedWithoutDeletingSavedWork() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let suite="NativeOnlyPolicy.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        defer {preferences.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
        // A convincing name/hash suffix must not substitute for checking its bytes.
        let id="SLOOP-2.7.1 · 7c9d269d",package=directory.appendingPathComponent(id).appendingPathExtension("fwsc")
        let bytes=Data(repeating:0x43,count:1024),save=directory.appendingPathComponent(id).appendingPathExtension("flash")
        let checkpoint=Data(repeating:0xA5,count:4096)
        try bytes.write(to:package);try checkpoint.write(to:save)
        preferences.set(id,forKey:FirmwareSelection.preferenceKey)
        let model=Instrument(directory:directory,preferences:preferences,nativeOnly:true)
        model.importFirmware(package)
        waitUntil {!model.busy && model.message != nil}
        XCTAssertTrue(model.firmwares.isEmpty);XCTAssertNil(model.selected)
        XCTAssertFalse(model.running);XCTAssertFalse(model.supportsExperimentalWASM)
        XCTAssertEqual(try Data(contentsOf:package),bytes)
        XCTAssertEqual(try Data(contentsOf:save),checkpoint)
        XCTAssertEqual(preferences.string(forKey:FirmwareSelection.preferenceKey),id)
    }

    func testRememberedExperimentalChoiceUsesNativeAndRetainsSeparateSave()throws {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let sources=[docs.appendingPathComponent("Native16Packages"),docs.appendingPathComponent("Native13Packages"),docs.appendingPathComponent("Firmwares")]
        let packages=sources.flatMap {(try? FileManager.default.contentsOfDirectory(at:$0,includingPropertiesForKeys:nil)) ?? []}
        var bytes:Data?
        for package in packages where package.pathExtension == "fwsc" {
            guard let data=try? Data(contentsOf:package) else {continue}
            let kind=data.withUnsafeBytes {instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,data.count)}
            if kind == 2 {bytes=data;break}
        }
        guard let bytes else {throw XCTSkip("Requires pinned local SLOOP; never downloads")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let suite="NativeOnlyPolicy.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!,id="native-only-sloop"
        try bytes.write(to:directory.appendingPathComponent(id).appendingPathExtension("fwsc"))
        let oldBranch=directory.appendingPathComponent(id).appendingPathExtension("wasm.flash"),sentinel=Data(repeating:0xA5,count:1<<20)
        try sentinel.write(to:oldBranch)
        preferences.set(id,forKey:FirmwareSelection.preferenceKey)
        preferences.set("wasm",forKey:SloopExecutionMode.preferenceKey)
        preferences.set("wasm",forKey:"firmwareEngine.\(id)")
        #if FM1_RESEARCH
        let model=Instrument(directory:directory,preferences:preferences,webEngineFactory:{
            XCTFail("Curated mode must never construct the experimental engine")
            throw NSError(domain:"UnexpectedWebEngine",code:1)
        },nativeOnly:true)
        #else
        let model=Instrument(directory:directory,preferences:preferences,nativeOnly:false)
        #endif
        defer {
            model.pause();waitUntil {!model.busy && !model.running}
            preferences.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)
        }
        model.sceneChanged(active:true)
        waitUntil {!model.busy && model.running}
        XCTAssertNil(model.message);XCTAssertEqual(model.selected?.id,id)
        XCTAssertEqual(model.executionMode,.native);XCTAssertEqual(model.nativeBackendName,"SLOOP")
        XCTAssertFalse(model.supportsExperimentalWASM);XCTAssertFalse(model.supportsClockControl)
        #if FM1_RESEARCH
        model.setExecutionMode(.wasm)
        #endif
        XCTAssertEqual(model.executionMode,.native);XCTAssertFalse(model.busy)
        XCTAssertEqual(try Data(contentsOf:oldBranch),sentinel)
    }
    private func waitUntil(_ predicate:@escaping ()->Bool,file:StaticString=#filePath,line:UInt=#line) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in predicate()},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:20),.completed,file:file,line:line)
    }
}
