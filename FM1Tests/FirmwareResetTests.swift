import XCTest
import AVFoundation
import CryptoKit
@testable import FM1

/// Exact local packages only; all saved data and recovery copies are disposable.
@MainActor final class FirmwareResetTests:XCTestCase {
    private final class Gate:@unchecked Sendable {
        private let lock=NSLock()
        private var remaining=0
        private var action:(()->Void)?
        func fail(_ count:Int){lock.lock();remaining=count;lock.unlock()}
        func before()throws {
            lock.lock();let reject=remaining>0;if reject {remaining-=1};lock.unlock()
            if reject {throw NSError(domain:"ResetTestAudioStart",code:1)}
        }
        func after(_ body:@escaping ()->Void){lock.lock();action=body;lock.unlock()}
        func started(){lock.lock();let body=action;action=nil;lock.unlock();body?()}
    }
    private struct Fixture {
        let model:Instrument,worker:DispatchQueue,root:URL,directory:URL,save:URL,package:Data,gate:Gate
        let preferences:UserDefaults,suite:String
    }
    private func packages()throws->[UInt32:Data] {
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        var result:[UInt32:Data]=[:]
        for name in ["Native16Packages","Community29Packages","NativeCommunityPackages","Firmwares"] {
            for url in (try? FileManager.default.contentsOfDirectory(at:documents.appendingPathComponent(name),includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "fwsc" {
                let data=try Data(contentsOf:url)
                let kind=data.withUnsafeBytes{instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,data.count)}
                if kind != 0 {result[kind]=data}
            }
        }
        return result
    }
    private func until(_ ready:()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+20
        while !ready() {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw NSError(domain:"ResetTestTimeout",code:1)}
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    private func idle(_ model:Instrument,_ running:Bool)async throws {try await until {!model.busy && model.running == running}}
    private func fixture(kind:UInt32=2,marker:Bool=false)async throws->Fixture {
        guard let package=try packages()[kind] else {throw XCTSkip("Requires the exact local native package for kind \(kind); no downloads")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("FirmwareReset-\(UUID().uuidString)")
        let directory=root.appendingPathComponent("Firmwares"),id="Reset-fixture-\(kind)",suite="FirmwareReset.\(UUID().uuidString)"
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try package.write(to:directory.appendingPathComponent(id).appendingPathExtension("fwsc"))
        let save=directory.appendingPathComponent(id).appendingPathExtension(kind == 6 ? "preview.flash" : "flash")
        let worker=DispatchQueue(label:suite),gate=Gate(),preferences=UserDefaults(suiteName:suite)!
        if marker {
            let data:Data=try await withCheckedThrowingContinuation {continuation in
                worker.async {
                    var error=[UInt8](repeating:0,count:512)
                    guard let machine=package.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress,package.count,&error,512)}) else {continuation.resume(throwing:NSError(domain:"ResetFixture",code:1));return}
                    defer{instrument_destroy(machine)}
                    var audio=[Float](repeating:0,count:1024);_=instrument_render(machine,&audio,512)
                    let size=instrument_flash(machine,nil,0)
                    var image=Data(count:size)
                    image.withUnsafeMutableBytes{_=instrument_flash(machine,$0.bindMemory(to:UInt8.self).baseAddress,size)}
                    image[123] ^= 0x5a
                    continuation.resume(returning:image)
                }
            }
            try data.write(to:save)
        }
        let model=Instrument(directory:directory,preferences:preferences,worker:worker,beforeEngineStart:{try gate.before()},afterEngineStart:{_ in gate.started()},nativeOnly:true)
        let f=Fixture(model:model,worker:worker,root:root,directory:directory,save:save,package:package,gate:gate,preferences:preferences,suite:suite)
        do {
            try await until {!model.firmwares.isEmpty}
            XCTAssertTrue(model.load(try XCTUnwrap(model.firmwares.first)));try await idle(model,true)
            model.pause();try await idle(model,false)
            return f
        } catch {await cleanup(f);throw error}
    }
    private func cleanup(_ f:Fixture)async {
        f.gate.fail(0);f.model.pause();try? await idle(f.model,false)
        f.preferences.removePersistentDomain(forName:f.suite)
        try? FileManager.default.removeItem(at:f.root)
    }
    private func original(_ token:FirmwareResetRecovery)throws->Data {try Data(contentsOf:token.backupURL)}
    private func sha(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private func expectFailure(_ action:()async throws->Void)async {
        do {try await action();XCTFail("Replacement unexpectedly succeeded")}
        catch {}
    }

    func testSloopResetAndSavedDataRestoreKeepOtherReleasesNamedProjectsAndHostSettings()async throws {
        let f=try await fixture();addTeardownBlock { @MainActor in await self.cleanup(f) }
        let store=ProjectFilesStore(instrument:f.model,directory:f.root.appendingPathComponent("Projects"))
        let defaults=try await f.model.captureSloopExportContext().snapshot
        let tone=SampleAudioSource(name:"Reset synthetic tone",samples:(0..<2205).map{Float(sin(Double($0)*0.13)*0.3)},sourceRate:22050,sourceChannels:1)
        let sample=try SampleAudioImporter.encode(source:tone,start:0,end:tone.duration)
        try await store.importSample(slotData:sample,slot:1,name:"Keep this sound",targetTrack:1)
        await store.saveCurrent(name:"Keep named project")
        let named=try XCTUnwrap(store.items.first(where:{$0.kind == .project})),namedBytes=try Data(contentsOf:named.url)
        let other=f.directory.appendingPathComponent("Other-release.flash"),otherBytes=Data(repeating:0x4a,count:4096)
        let research=f.directory.appendingPathComponent("Reset-fixture-2.wasm.flash"),researchBytes=Data(repeating:0xb2,count:4096)
        try otherBytes.write(to:other);try researchBytes.write(to:research)
        f.model.master(0.41);f.model.toggleMute()
        let previous=try Data(contentsOf:f.save)
        // Disk is deliberately older/different than the live native image.
        var stale=previous;stale[123] ^= 1;try stale.write(to:f.save)
        let selected=f.model.selected
        let token=try await f.model.resetCurrentFirmware();try await idle(f.model,false)
        XCTAssertEqual(try original(token),previous,"Back up live native saved data, not a stale disk file")
        let receipt=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:token.backupURL.deletingLastPathComponent().appendingPathComponent("receipt.json"))) as? [String:Any])
        XCTAssertEqual(receipt["firmwareID"] as? String,selected?.id)
        XCTAssertEqual(receipt["nativeKind"] as? Int,2)
        XCTAssertEqual(receipt["packageSHA256"] as? String,sha(f.package))
        XCTAssertEqual(receipt["packageVersion"] as? String,"2.8")
        XCTAssertEqual(receipt["originalSHA256"] as? String,sha(previous))
        let reset=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try reset.bytes("sample1"),try defaults.bytes("sample1"))
        XCTAssertNotEqual(try reset.bytes("sample1"),sample)
        XCTAssertEqual(f.model.selected,selected);XCTAssertEqual(f.model.volume,0.41);XCTAssertTrue(f.model.muted)
        XCTAssertFalse(f.model.playbackWanted);XCTAssertNotNil(f.model.screen)
        XCTAssertTrue(f.model.load(try XCTUnwrap(selected)));try await idle(f.model,true)
        f.model.pause();try await idle(f.model,false)
        let reopened=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try reopened.bytes("sample1"),try defaults.bytes("sample1"))
        try await f.model.restoreFirmwareReset(token);try await idle(f.model,false)
        let restored=try await f.model.captureSloopExportContext().snapshot
        XCTAssertEqual(try restored.bytes("sample1"),sample)
        XCTAssertEqual(try Data(contentsOf:other),otherBytes);XCTAssertEqual(try Data(contentsOf:research),researchBytes)
        XCTAssertEqual(try Data(contentsOf:named.url),namedBytes)
        XCTAssertEqual(try original(token),previous,"Restore must not consume its recovery copy")
    }

    func testAllFifteenNativeFormatsResetAndRestoreWhilePaused()async throws {
        let required=(2...9).map{UInt32($0)}+(11...17).map{UInt32($0)}
        let installed=try packages()
        guard required.allSatisfy({installed[$0] != nil}) else {throw XCTSkip("Requires all fifteen exact native packages in the isolated simulator")}
        for kind in required {
            let f=try await fixture(kind:kind)
            do {
                let token=try await f.model.resetCurrentFirmware();try await idle(f.model,false)
                XCTAssertEqual(try original(token).count,kind == 6 ? 536576 : 1<<20,"kind \(kind)")
                try await f.model.restoreFirmwareReset(token);try await idle(f.model,false)
                XCTAssertEqual(try Data(contentsOf:f.save).count,kind == 6 ? 536576 : 1<<20)
                XCTAssertFalse(f.model.playbackWanted);XCTAssertNotNil(f.model.screen);XCTAssertNil(f.model.message)
                await cleanup(f)
            } catch {await cleanup(f);throw error}
        }
    }

    func testBackupFailureLeavesOriginalEngineDiskAndRunningIntent()async throws {
        let f=try await fixture(marker:true);addTeardownBlock { @MainActor in await self.cleanup(f) }
        f.model.resume();try await idle(f.model,true)
        let previous=try Data(contentsOf:f.save),blocker=Data("Keep this recovery-location file".utf8)
        try blocker.write(to:f.directory.appendingPathComponent("ResetRecovery"))
        await expectFailure {_=try await f.model.resetCurrentFirmware()}
        try await idle(f.model,true)
        XCTAssertEqual(try Data(contentsOf:f.save),previous)
        XCTAssertEqual(try Data(contentsOf:f.directory.appendingPathComponent("ResetRecovery")),blocker)
        XCTAssertTrue(f.model.playbackWanted);XCTAssertNil(f.model.message)
    }

    func testCandidateStartFailurePreservesOldDiskAndRestartsOldEngine()async throws {
        let f=try await fixture(marker:true);addTeardownBlock { @MainActor in await self.cleanup(f) }
        f.model.resume();try await idle(f.model,true)
        let previous=try Data(contentsOf:f.save),selected=f.model.selected
        f.gate.fail(1)
        await expectFailure {_=try await f.model.resetCurrentFirmware()}
        try await idle(f.model,true)
        XCTAssertEqual(try Data(contentsOf:f.save),previous);XCTAssertEqual(f.model.selected,selected)
        XCTAssertTrue(f.model.playbackWanted);XCTAssertNil(f.model.message)
    }

    func testDoubleAudioStartFailureShowsRetryableResumeWithoutLosingSavedData()async throws {
        let f=try await fixture(marker:true);addTeardownBlock { @MainActor in await self.cleanup(f) }
        f.model.resume();try await idle(f.model,true)
        let previous=try Data(contentsOf:f.save)
        f.gate.fail(2)
        await expectFailure {_=try await f.model.resetCurrentFirmware()}
        try await idle(f.model,false)
        XCTAssertFalse(f.model.playbackWanted);XCTAssertNil(f.model.message)
        XCTAssertEqual(try Data(contentsOf:f.save),previous)
        f.model.resume();try await idle(f.model,true);XCTAssertTrue(f.model.playbackWanted)
    }

    func testLatePauseAndRenameFailureNeverCheckpointAnUncommittedCandidate()async throws {
        let f=try await fixture(marker:true);addTeardownBlock { @MainActor in await self.cleanup(f) }
        f.model.resume();try await idle(f.model,true)
        let previous=try Data(contentsOf:f.save)
        f.gate.after {
            // Hold subsequent lifecycle work so its legitimate old-state save
            // cannot mask an erroneous candidate checkpoint before the assertion.
            f.worker.suspend()
            DispatchQueue.main.sync {f.model.pause()}
            let root=f.directory.appendingPathComponent("ResetRecovery")
            let folders=(try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
            for folder in folders {
                let stage=folder.appendingPathComponent("replacement.flash")
                if FileManager.default.fileExists(atPath:stage.path) {try? FileManager.default.moveItem(at:stage,to:folder.appendingPathComponent("held-replacement.flash"))}
            }
        }
        await expectFailure {_=try await f.model.resetCurrentFirmware()}
        XCTAssertEqual(try Data(contentsOf:f.save),previous)
        XCTAssertFalse(f.model.playbackWanted)
        f.worker.resume();try await idle(f.model,false)
        XCTAssertEqual(try Data(contentsOf:f.save),previous);XCTAssertNil(f.model.message)
    }

    func testRecoveryRejectsTamperedDataReceiptAndDifferentCurrentRelease()async throws {
        let f=try await fixture(marker:true);addTeardownBlock { @MainActor in await self.cleanup(f) }
        let token=try await f.model.resetCurrentFirmware();try await idle(f.model,false)
        let saved=try Data(contentsOf:f.save),backup=try original(token)
        var altered=backup;altered[123] ^= 1;try altered.write(to:token.backupURL)
        await expectFailure {try await f.model.restoreFirmwareReset(token)}
        XCTAssertEqual(try Data(contentsOf:f.save),saved)
        try backup.write(to:token.backupURL)
        let receiptURL=token.backupURL.deletingLastPathComponent().appendingPathComponent("receipt.json"),receipt=try Data(contentsOf:receiptURL)
        try (receipt+Data("\n".utf8)).write(to:receiptURL)
        await expectFailure {try await f.model.restoreFirmwareReset(token)}
        XCTAssertEqual(try Data(contentsOf:f.save),saved)
        try receipt.write(to:receiptURL)
        guard let other=try packages()[11] else {throw XCTSkip("Requires exact local CoralFlower to test cross-release rejection")}
        let otherURL=f.directory.appendingPathComponent("Other-native.fwsc");try other.write(to:otherURL)
        XCTAssertTrue(f.model.load(Firmware(id:"Other-native",name:"Other native",url:otherURL)));try await idle(f.model,true)
        f.model.pause();try await idle(f.model,false)
        let otherSave=f.directory.appendingPathComponent("Other-native.flash"),otherBefore=try Data(contentsOf:otherSave)
        await expectFailure {try await f.model.restoreFirmwareReset(token)}
        XCTAssertEqual(try Data(contentsOf:otherSave),otherBefore);XCTAssertNil(f.model.message)
    }
}
