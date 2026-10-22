#if FM1_RESEARCH
import XCTest
import SwiftUI
import CryptoKit
@testable import FM1

@MainActor final class WebEngineIntegrationTests:XCTestCase {
    func testActualWKWorkerAudioAndSeparateSaveRoundtrip()throws {
        let idleTimerWasDisabled=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        defer {UIApplication.shared.isIdleTimerDisabled=idleTimerWasDisabled}
        let source=Instrument()
        guard let firmware=source.firmwares.first(where:{$0.name == "SLOOP-2.7.1"}) else {throw XCTSkip("Requires the dedicated simulator's installed SLOOP package; never downloads")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let package=directory.appendingPathComponent("SLOOP-2.7.1.fwsc")
        try FileManager.default.copyItem(at:firmware.url,to:package)
        let suite="WebEngineTests.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        let model=Instrument(directory:directory,preferences:preferences)
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else {throw XCTSkip("Requires a hosted foreground window scene")}
        let window=UIWindow(windowScene:scene)
        window.frame=scene.coordinateSpace.bounds
        window.rootViewController=UIHostingController(rootView:InstrumentView(instrument:model))
        window.makeKeyAndVisible()
        defer {
            model.pause();settle(model,running:false,timeout:25)
            window.isHidden=true;window.rootViewController=nil
            preferences.removePersistentDomain(forName:suite)
            try? FileManager.default.removeItem(at:directory)
        }
        model.sceneChanged(active:true);settle(model,running:true)
        XCTAssertTrue(model.supportsExperimentalWASM)
        XCTAssertEqual(model.executionMode,.native)
        model.pause();settle(model,running:false)
        let nativeURL=directory.appendingPathComponent("SLOOP-2.7.1.flash")
        let nativeBefore=try Data(contentsOf:nativeURL)
        XCTAssertEqual(nativeBefore.count,1<<20)
        model.setExecutionMode(.wasm);settle(model,running:false,timeout:65)
        XCTAssertNil(model.message)
        guard model.executionMode == .wasm else {XCTFail("Actual WK load failed: \(model.message ?? model.status)");return}
        let context:[String:Any]=["applicationState":UIApplication.shared.applicationState.rawValue,"sceneState":scene.activationState.rawValue,"attachedWindow":model.experimentalWebView?.window != nil,"windowHidden":window.isHidden,"windowAlpha":window.alpha,"webHidden":model.experimentalWebView?.isHidden ?? true,"webAlpha":model.experimentalWebView?.alpha ?? 0,"webFrame":model.experimentalWebView.map{String(describing:$0.frame)} ?? "none"]
        let attachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:context,options:[.prettyPrinted,.sortedKeys]),uniformTypeIdentifier:"public.json")
        attachment.name="WK foreground attachment";attachment.lifetime = .keepAlways;add(attachment)
        print("WK foreground attachment \(context)")
        XCTAssertEqual(preferences.string(forKey:SloopExecutionMode.preferenceKey),"wasm")
        let initialWASMURL=directory.appendingPathComponent("SLOOP-2.7.1.wasm.flash")
        XCTAssertEqual(try Data(contentsOf:initialWASMURL),nativeBefore,"Paused WK snapshot must survive owned transfer, host encoding and Swift decoding byte-for-byte")
        model.resume();settle(model,running:true,timeout:30)
        model.key(21,true)
        let played=expectation(description:"Worker and worklet render")
        DispatchQueue.main.asyncAfter(deadline:.now()+3) {played.fulfill()}
        wait(for:[played],timeout:5)
        model.key(21,false)
        var diagnostics:AudioDiagnostics?
        let capture=expectation(description:"Actual WK metrics")
        model.captureAudioDiagnostics {diagnostics=$0;capture.fulfill()}
        wait(for:[capture],timeout:5)
        XCTAssertEqual(diagnostics?.backend,.wasm)
        XCTAssertEqual(diagnostics?.wasmModuleSHA256,SloopExecutionMode.moduleSHA256)
        XCTAssertEqual(diagnostics?.guestClockHz,240000000)
        XCTAssertEqual(diagnostics?.counterScope,"engine-instance-lifetime")
        XCTAssertGreaterThan(diagnostics?.audioContextSampleRate ?? 0,0)
        XCTAssertEqual(diagnostics?.inputSampleRate,44100)
        XCTAssertGreaterThan(diagnostics?.renderRatioMax ?? 0,0)
        XCTAssertEqual(diagnostics?.elapsedSeconds ?? -1,diagnostics?.outputCounterElapsedSeconds ?? -2,accuracy:0.001)
        XCTAssertGreaterThan(diagnostics?.outputDeliveredFrames ?? 0,0,"The AudioWorklet must actually consume PCM")
        XCTAssertGreaterThan(diagnostics?.wasmCompiledRegions ?? 0,0,"Actual WK must compile translated regions")
        XCTAssertEqual(diagnostics?.wasmCompilationFailures,0)
        XCTAssertGreaterThan(diagnostics?.wasmNonzeroInputSamples ?? 0,0,"The actual WK engine must produce a nonzero note signal")
        if let diagnostics {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
            let data=try encoder.encode(diagnostics)
            let report=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");report.name="Actual WK audio diagnostics";report.lifetime = .keepAlways;add(report)
            let destination=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("PerformanceReports/ModeSwitch12",isDirectory:true)
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            try data.write(to:destination.appendingPathComponent("ActualWK.json"),options:.atomic)
        }
        model.pause();settle(model,running:false,timeout:25)
        let wasmURL=directory.appendingPathComponent("SLOOP-2.7.1.wasm.flash")
        XCTAssertEqual(try Data(contentsOf:wasmURL).count,1<<20)
        XCTAssertEqual(try Data(contentsOf:nativeURL),nativeBefore,"Experimental checkpoints must never overwrite native sounds")
        model.sceneChanged(active:false);model.sceneChanged(active:true);settle(model,running:false)
        model.setExecutionMode(.native);settle(model,running:false,timeout:30)
        XCTAssertEqual(model.executionMode,.native)
        XCTAssertEqual(try Data(contentsOf:nativeURL),nativeBefore)
        XCTAssertEqual(model.playbackWanted,false,"Mode switching preserves an explicit pause")
        XCTAssertNil(model.message)
    }
    private func settle(_ model:Instrument,running:Bool,timeout:TimeInterval=20,file:StaticString=#filePath,line:UInt=#line) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.busy && model.running == running},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:timeout),.completed,"\(model.status): \(model.message ?? "no error")",file:file,line:line)
    }
}

#endif
