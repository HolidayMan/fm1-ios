import XCTest
import CryptoKit
@testable import FM1

/// Pinned public package only. Every writable store is a disposable test copy.
@MainActor final class ChoralRootIntegrationTests:XCTestCase {
    private let digest="a09f9e19b66a91351de37c532e0d15cdc03ff9e9c82a0b152cdb66ca3fdc0326"
    private func package()throws->Data {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        for folder in ["Choral31Packages","Native16Packages"] {
            for url in (try? FileManager.default.contentsOfDirectory(at:docs.appendingPathComponent(folder),includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "fwsc" {
                let data=try Data(contentsOf:url)
                if SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == digest {
                    XCTAssertEqual(data.count,610313)
                    return data
                }
            }
        }
        throw XCTSkip("Requires exact public ChoralRoot0.27 in dedicated Choral31Packages; never downloads")
    }
    private func until(_ predicate:()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+20
        while !predicate() {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw NSError(domain:"ChoralRootTestTimeout",code:1)}
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    private func idle(_ model:Instrument,_ running:Bool)async throws {try await until {!model.busy && model.running == running}}
    private func diagnostics(_ model:Instrument)async->AudioDiagnostics {
        await withCheckedContinuation {continuation in model.captureAudioDiagnostics {continuation.resume(returning:$0)}}
    }
    func testPinnedChoralRootCatalogueIsDistinctFromCoralFlowerAndNamesINITLimit()throws {
        let entry=try XCTUnwrap(CatalogFirmware.available.first(where:{$0.id == "choralroot"}))
        XCTAssertEqual(entry.name,"ChoralRoot");XCTAssertEqual(entry.version,"0.27")
        XCTAssertEqual(entry.sha256,digest);XCTAssertEqual(entry.size,610313)
        XCTAssertEqual(entry.filename,"ChoralRoot-0.27")
        XCTAssertEqual(entry.url,"https://github.com/Quixotic7/ChoralRootFM1/releases/download/v0.27/choralroot-0.27.fwsc")
        XCTAssertEqual(entry.nativeEngineName,"ChoralRoot · INIT banks")
        for word in ["CZ-1","Prophet-5","INIT"] {XCTAssertTrue(entry.summary?.contains(word) == true)}
        let coral=try XCTUnwrap(CatalogFirmware.available.first(where:{$0.id == "coralflower"}))
        XCTAssertEqual(coral.nativeEngineName,"CoralFlower")
        XCTAssertNotEqual(entry.filename,coral.filename);XCTAssertNotEqual(entry.sha256,coral.sha256)
        XCTAssertEqual(CatalogFirmware.available.count,15)
    }
    func testPhysicalMajorChordProducesFinitePCMAndThreeActualVoicesOnIndependentNativeCore()throws {
        let data=try package(),worker=DispatchQueue(label:"ChoralRootTest.Core")
        try worker.sync {
            func create()throws->UnsafeMutableRawPointer {
                var error=[UInt8](repeating:0,count:512)
                return try XCTUnwrap(data.withUnsafeBytes {instrument_create($0.bindMemory(to:UInt8.self).baseAddress,data.count,&error,512)})
            }
            let a=try create(),b=try create();defer{instrument_destroy(a);instrument_destroy(b)}
            XCTAssertEqual(instrument_native_kind(a),17);XCTAssertEqual(instrument_native_kind(b),17)
            var pcm=[Float](repeating:0,count:1024)
            func render(_ machine:UnsafeMutableRawPointer,_ blocks:Int) {
                for _ in 0..<blocks {XCTAssertEqual(instrument_render(machine,&pcm,512),512)}
            }
            func flash(_ machine:UnsafeMutableRawPointer)->Data {
                let count=instrument_flash(machine,nil,0);var result=Data(count:count)
                result.withUnsafeMutableBytes{XCTAssertEqual(instrument_flash(machine,$0.bindMemory(to:UInt8.self).baseAddress,count),count)}
                return result
            }
            render(a,16);render(b,16)
            let independentBefore=flash(b)
            // Source manual: hold A#3/MAJ (physical19), then D4/root (23).
            instrument_key(a,19,true);render(a,4);instrument_key(a,23,true)
            var nonzero=0,peak:Float=0
            for _ in 0..<64 {
                render(a,1)
                for sample in pcm {XCTAssertTrue(sample.isFinite);if abs(sample)>0.0001 {nonzero+=1};peak=max(peak,abs(sample))}
            }
            var metrics=[UInt64](repeating:0,count:16)
            XCTAssertEqual(instrument_workload_metrics(a,&metrics,16),16)
            XCTAssertGreaterThanOrEqual(metrics[1],3,"Count actual source chord DSP voices, not pressed keys")
            XCTAssertGreaterThan(nonzero,100);XCTAssertGreaterThan(peak,0.001)
            XCTAssertLessThanOrEqual(peak,1)
            instrument_release_all(a);render(a,8)
            var pixels=[UInt32](repeating:0,count:240*240),leds=[Float](repeating:0,count:41)
            _=instrument_snapshot(a,&pixels,&leds)
            XCTAssertGreaterThan(Set(pixels).count,4)
            XCTAssertEqual(flash(b),independentBefore,"Playing A must not mutate B's raw store")
            var bMetrics=[UInt64](repeating:0,count:16);_=instrument_workload_metrics(b,&bMetrics,16)
            XCTAssertEqual(bMetrics[1],0,"The untouched instance must not inherit A's chord voices")
            var saved=flash(a);XCTAssertEqual(saved.count,1<<20)
            saved[123] ^= 0x5a // Distinct byte in this disposable raw image, outside the musical object log.
            let c=try create();defer{instrument_destroy(c)}
            XCTAssertTrue(saved.withUnsafeBytes{instrument_restore(c,$0.bindMemory(to:UInt8.self).baseAddress,saved.count)})
            XCTAssertEqual(flash(c),saved,"A complete raw store must reopen without truncation or unrelated bank replacement")
            XCTAssertEqual(flash(b),independentBefore)
        }
    }
    func testDeviceCallbacksPausedResetRestoreAndReopenKeepSeparateCoralSavedData()async throws {
        let data=try package(),root=FileManager.default.temporaryDirectory.appendingPathComponent("Choral31-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let id="ChoralRoot-0.27",suite="Choral31.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        let packageURL=root.appendingPathComponent(id).appendingPathExtension("fwsc")
        try data.write(to:packageURL)
        let other=root.appendingPathComponent("CoralFlower-0.5.flash"),otherData=Data(repeating:0x37,count:1<<20)
        try otherData.write(to:other)
        let model=Instrument(directory:root,preferences:preferences,worker:DispatchQueue(label:suite),nativeOnly:true)
        addTeardownBlock { @MainActor in
            model.pause();try? await self.idle(model,false)
            preferences.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:root)
        }
        try await until {!model.firmwares.isEmpty}
        let firmware=try XCTUnwrap(model.firmwares.first)
        XCTAssertTrue(model.load(firmware));try await idle(model,true)
        XCTAssertEqual(model.nativeBackendName,"ChoralRoot · INIT banks")
        XCTAssertFalse(model.supportsProjectFiles);XCTAssertFalse(model.supportsClockControl);XCTAssertFalse(model.supportsExperimentalWASM)
        model.key(19,true);try await Task.sleep(nanoseconds:70_000_000);model.key(23,true)
        let deadline=ProcessInfo.processInfo.systemUptime+8
        var report=await diagnostics(model)
        while report.outputDeliveredFrames == 0 && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(nanoseconds:50_000_000);report=await diagnostics(model)
        }
        model.key(23,false);model.key(19,false)
        XCTAssertGreaterThan(report.outputDeliveredFrames,0,"The AVAudioEngine must consume PCM beyond prefill")
        // This public decoder is intentionally SLOOP-specific. ChoralRoot's
        // three actual DSP voices and finite nonzero PCM are proved separately
        // through its C ABI; do not reinterpret a missing report as silence.
        XCTAssertNil(report.nativeWorkload)
        XCTAssertNotNil(model.screen)
        // ChoralRoot saves sound/settings on a long SAVE, unlike CoralFlower's
        // automatic settings log. Exercise the real source control protocol.
        model.key(1,true);try await Task.sleep(nanoseconds:80_000_000);model.key(1,false)
        model.key(9,true);try await Task.sleep(nanoseconds:1_700_000_000);model.key(9,false)
        try await Task.sleep(nanoseconds:100_000_000)
        model.pause();try await idle(model,false)
        let save=root.appendingPathComponent(id).appendingPathExtension("flash"),before=try Data(contentsOf:save)
        XCTAssertEqual(before.count,1<<20)
        let token=try await model.resetCurrentFirmware();try await idle(model,false)
        XCTAssertEqual(try Data(contentsOf:token.backupURL),before)
        XCTAssertEqual(token.firmwareID,id)
        let receipt=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:token.backupURL.deletingLastPathComponent().appendingPathComponent("receipt.json"))) as? [String:Any])
        XCTAssertEqual(receipt["nativeKind"] as? Int,17);XCTAssertEqual(receipt["packageVersion"] as? String,"0.27")
        XCTAssertFalse(model.playbackWanted);XCTAssertEqual(model.selected,firmware)
        XCTAssertNotEqual(try Data(contentsOf:save),before,"Reset must replace the explicitly saved edited settings")
        try await model.restoreFirmwareReset(token);try await idle(model,false)
        XCTAssertFalse(model.playbackWanted);XCTAssertNil(model.message)
        XCTAssertEqual(try Data(contentsOf:save),before,"Restore must recover the complete saved ChoralRoot data")
        XCTAssertEqual(try Data(contentsOf:other),otherData)
        XCTAssertTrue(model.load(firmware));try await idle(model,true)
        XCTAssertEqual(model.nativeBackendName,"ChoralRoot · INIT banks");XCTAssertNotNil(model.screen)
        XCTAssertNil(model.message)
        model.pause();try await idle(model,false)
        XCTAssertEqual(try Data(contentsOf:other),otherData)
    }
}
