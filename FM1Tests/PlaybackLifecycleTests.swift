import XCTest
import AVFoundation
@testable import FM1

final class PlaybackPolicyTests:XCTestCase {
    func testColdLaunchStartsButManualPauseSurvivesSceneChanges() {
        var policy=PlaybackPolicy()
        XCTAssertFalse(policy.shouldRun)
        XCTAssertTrue(policy.scene(active:true,autoStart:true));XCTAssertTrue(policy.shouldRun)
        _=policy.scene(active:false,autoStart:true);XCTAssertFalse(policy.shouldRun)
        _=policy.scene(active:true,autoStart:true);XCTAssertTrue(policy.shouldRun)
        policy.pause();_=policy.scene(active:false,autoStart:true);_=policy.scene(active:true,autoStart:true)
        XCTAssertFalse(policy.shouldRun)
        var cold=PlaybackPolicy();_=cold.scene(active:true,autoStart:true)
        XCTAssertTrue(cold.shouldRun,"Manual pause belongs to this process, not future launches")
    }
    func testInterruptionAuthorizationAndDisconnectCannotOverrideManualPause() {
        var policy=PlaybackPolicy();policy.play();policy.interruptionBegan()
        XCTAssertFalse(policy.shouldRun)
        policy.pause();policy.interruptionEnded(shouldResume:true);XCTAssertFalse(policy.shouldRun)
        policy.play();policy.interruptionBegan();policy.interruptionEnded(shouldResume:false)
        _=policy.scene(active:true,autoStart:true);XCTAssertFalse(policy.shouldRun)
        policy.play();XCTAssertTrue(policy.shouldRun)
        policy.hold();_=policy.scene(active:false,autoStart:true);_=policy.scene(active:true,autoStart:true)
        XCTAssertFalse(policy.shouldRun);policy.play();XCTAssertTrue(policy.shouldRun)
    }
    func testLifecycleFixtureCannotEscapeIntoOwnerLibrary() throws {
        let docs=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:docs)}
        let safe=docs.appendingPathComponent("PerformanceFixtures/owner")
        try FileManager.default.createDirectory(at:safe,withIntermediateDirectories:true)
        XCTAssertEqual(AppLaunchFixture.resolve("Documents/PerformanceFixtures/owner",documents:docs),safe.resolvingSymlinksInPath())
        for path in ["Documents/Firmwares","Documents/PerformanceFixtures/../Firmwares","/Documents/PerformanceFixtures/owner","Documents/PerformanceFixtures/missing"] {
            XCTAssertNil(AppLaunchFixture.resolve(path,documents:docs))
        }
        let link=docs.appendingPathComponent("PerformanceFixtures/escape")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:docs)
        XCTAssertNil(AppLaunchFixture.resolve("Documents/PerformanceFixtures/escape",documents:docs))
    }
    func testDiagnosticLaunchDoesNotRequestAudioAndFailureGateNeedsExplicitClear() {
        var policy=PlaybackPolicy();_=policy.scene(active:true,autoStart:false)
        XCTAssertFalse(policy.shouldRun)
        let demand=PlaybackDemand();demand.set(true);demand.fail(epoch:demand.epoch);demand.set(true)
        XCTAssertFalse(demand.shouldRun);demand.clearFailure();XCTAssertTrue(demand.shouldRun)
    }
}

@MainActor final class PlaybackLifecycleTests:XCTestCase {
    private struct Fixture {
        let model:Instrument, worker:DispatchQueue, directory:URL, preferences:UserDefaults
        let suite:String
    }
    private func fixture(valid:Bool=true,beforeEngineStart:(() throws -> Void)?=nil,afterEngineStart:((AVAudioEngine)->Void)?=nil,waitForDiscovery:Bool=true)throws->Fixture {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let suite="LifecycleTests.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        let destination=directory.appendingPathComponent("SLOOP-2.8.fwsc")
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let sources=[documents.appendingPathComponent("Native16Packages"),documents.appendingPathComponent("Firmwares")]
        var bytes:Data?
        for folder in sources {
            for file in (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? [] where file.pathExtension == "fwsc" {
                guard let data=try? Data(contentsOf:file) else {continue}
                let kind=data.withUnsafeBytes {instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,data.count)}
                if kind == 2 {bytes=data;break}
            }
            if bytes != nil {break}
        }
        guard let bytes else {
            try? FileManager.default.removeItem(at:directory)
            throw XCTSkip("Requires the exact linked local SLOOP fixture; never downloads")
        }
        try bytes.write(to:destination)
        let worker=DispatchQueue(label:"LifecycleTests.worker")
        let model=Instrument(directory:directory,preferences:preferences,worker:worker,beforeEngineStart:beforeEngineStart,afterEngineStart:afterEngineStart,nativeOnly:true)
        if waitForDiscovery {
            let scanned=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in model.selected != nil},object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[scanned],timeout:15),.completed)
        }
        // Test a real race: content becomes invalid after exact startup probing,
        // before the serial loader reads it. Store scanning must never offer
        // invalid bytes merely to trigger an error in a test.
        if !valid {try Data([0]).write(to:destination)}
        return Fixture(model:model,worker:worker,directory:directory,preferences:preferences,suite:suite)
    }

    private func idle(_ model:Instrument,running:Bool,file:StaticString=#filePath,line:UInt=#line) {
        let done=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.busy && model.running == running},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[done],timeout:15),.completed,"Playback did not settle: \(model.status), \(model.message ?? "no error")",file:file,line:line)
    }
    private func cleanup(_ fixture:Fixture) {
        fixture.model.pause();idle(fixture.model,running:false)
        fixture.preferences.removePersistentDomain(forName:fixture.suite)
        try? FileManager.default.removeItem(at:fixture.directory)
    }
    private func asyncFixture(afterEngineStart:((AVAudioEngine)->Void)?=nil)async throws->Fixture {
        let f=try fixture(afterEngineStart:afterEngineStart,waitForDiscovery:false)
        let until=ProcessInfo.processInfo.systemUptime+15
        while f.model.selected == nil {
            guard ProcessInfo.processInfo.systemUptime<until else {throw ProjectFilesError("Async fixture discovery did not complete")}
            try await Task.sleep(nanoseconds:20_000_000)
        }
        return f
    }
    private func settle(_ model:Instrument,running:Bool)async throws {
        let until=ProcessInfo.processInfo.systemUptime+15
        while model.busy || model.running != running {
            guard ProcessInfo.processInfo.systemUptime<until else {throw ProjectFilesError("Playback did not settle: \(model.status), \(model.message ?? "no error")")}
            try await Task.sleep(nanoseconds:20_000_000)
        }
    }
    private func cleanupAsync(_ f:Fixture)async {
        f.model.pause();try? await settle(f.model,running:false)
        f.preferences.removePersistentDomain(forName:f.suite)
        try? FileManager.default.removeItem(at:f.directory)
    }
    func testActivationDuringPendingLoadAndRapidSceneCheckpointResumesLatestIntent() throws {
        let f=try fixture();defer{cleanup(f)}
        f.worker.suspend()
        f.model.sceneChanged(active:true)
        XCTAssertTrue(f.model.busy)
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true)
        f.worker.resume();idle(f.model,running:true)
        XCTAssertEqual(f.model.selected?.name,"SLOOP-2.8")
        f.worker.suspend()
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true)
        f.worker.resume();idle(f.model,running:true)
        XCTAssertNil(f.model.message)
    }
    func testManualPauseCancelsPendingAutomaticResumeAndPersistsWithinRun() throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);idle(f.model,running:true)
        f.worker.suspend()
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);f.model.pause()
        XCTAssertFalse(f.model.playbackWanted)
        f.worker.resume();idle(f.model,running:false)
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);idle(f.model,running:false)
        f.model.resume();idle(f.model,running:true)
    }
    func testManualPauseWhileInitialLoadPendingNeverStartsAudio() throws {
        let f=try fixture();defer{cleanup(f)}
        f.worker.suspend();f.model.sceneChanged(active:true);f.model.pause();f.worker.resume()
        idle(f.model,running:false)
        XCTAssertNotNil(f.model.selected)
        XCTAssertNotNil(f.model.screen,"A loaded native LCD must replace CHOOSE FIRMWARE without any audio callbacks")
        if let data=f.model.screen?.dataProvider?.data {
            let pixels=(data as Data).withUnsafeBytes {Set($0.bindMemory(to:UInt32.self))}
            XCTAssertGreaterThan(pixels.count,1,"The paused LCD must contain drawn content, not a blank surface")
        }
        var diagnostics:AudioDiagnostics?
        let captured=expectation(description:"Paused loaded firmware")
        f.model.captureAudioDiagnostics {diagnostics=$0;captured.fulfill()}
        wait(for:[captured],timeout:5)
        XCTAssertEqual(diagnostics?.outputFrames,0)
    }
    func testRealNotificationBridgeHonorsShouldResumeAndRouteHold() throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);idle(f.model,running:true)
        func interruption(_ type:AVAudioSession.InterruptionType,resume:Bool=false) {
            NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:AVAudioSession.sharedInstance(),userInfo:[AVAudioSessionInterruptionTypeKey:type.rawValue,AVAudioSessionInterruptionOptionKey:resume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0])
        }
        interruption(.began);idle(f.model,running:false)
        interruption(.ended,resume:true);idle(f.model,running:true)
        interruption(.began);f.model.pause();interruption(.ended,resume:true);idle(f.model,running:false)
        f.model.resume();idle(f.model,running:true)
        interruption(.began);interruption(.ended,resume:false);idle(f.model,running:false)
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);idle(f.model,running:false)
        f.model.resume();idle(f.model,running:true)
        NotificationCenter.default.post(name:AVAudioSession.routeChangeNotification,object:AVAudioSession.sharedInstance(),userInfo:[AVAudioSessionRouteChangeReasonKey:AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        idle(f.model,running:false)
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);idle(f.model,running:false)
        f.model.resume();idle(f.model,running:true)
    }
    func testExplicitRetryBeforeOldFailurePublicationKeepsNewIntent() throws {
        let f=try fixture(valid:false);defer{cleanup(f)}
        f.model.resume()
        // Hold main until the failed worker has queued its publication, then issue
        // a new public Play before that old main callback is allowed to execute.
        f.worker.sync {}
        f.worker.suspend()
        f.model.resume()
        let published=expectation(description:"Old failure publication drained")
        DispatchQueue.main.async {
            XCTAssertTrue(f.model.playbackWanted,"An older failure must not cancel a newer explicit Play")
            XCTAssertNil(f.model.message)
            published.fulfill()
        }
        wait(for:[published],timeout:5)
        f.worker.resume();idle(f.model,running:false)
        XCTAssertNotNil(f.model.message,"The new invalid load must still fail and hold normally")
    }
    func testFailureIsHeldUntilExplicitPlayAndDiagnosticActivationStaysIdle() throws {
        let f=try fixture(valid:false);defer{cleanup(f)}
        f.model.sceneChanged(active:true,autoStart:false);idle(f.model,running:false)
        XCTAssertNil(f.model.message)
        f.model.resume();idle(f.model,running:false);XCTAssertNotNil(f.model.message)
        f.model.message=nil
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);idle(f.model,running:false)
        XCTAssertNil(f.model.message,"Scene activation must not repeatedly retry a failed firmware")
        f.model.resume();idle(f.model,running:false);XCTAssertNotNil(f.model.message)
    }
    func testBusySelectionIsRejectedExplicitlyAndRetryWorksAfterCheckpoint() throws {
        let f=try fixture();defer{cleanup(f)}
        let firmware=try XCTUnwrap(f.model.selected)
        f.worker.suspend()
        f.model.sceneChanged(active:false,autoStart:false)
        XCTAssertTrue(f.model.busy)
        XCTAssertFalse(f.model.load(firmware),"The chooser must not dismiss an ignored selection")
        f.worker.resume();idle(f.model,running:false)
        f.model.sceneChanged(active:true,autoStart:false);idle(f.model,running:false)
        XCTAssertTrue(f.model.load(firmware));idle(f.model,running:true)
        XCTAssertEqual(f.model.selected,firmware);XCTAssertNil(f.model.message)
    }
    func testFailedImportAcrossBackgroundReleasesBusyAndNextSelectionStarts() throws {
        let f=try fixture();defer{cleanup(f)}
        let firmware=try XCTUnwrap(f.model.selected)
        let invalid=f.directory.appendingPathComponent("invalid-import.fwsc")
        try Data(repeating:0,count:1024).write(to:invalid)
        f.model.selected=nil
        f.worker.suspend()
        f.model.importFirmware(invalid,removeAfterImport:true)
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true)
        XCTAssertFalse(f.model.load(firmware))
        f.worker.resume();idle(f.model,running:false)
        XCTAssertNotNil(f.model.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath:invalid.path))
        f.model.message=nil
        XCTAssertTrue(f.model.load(firmware));idle(f.model,running:true)
        XCTAssertEqual(f.model.selected,firmware);XCTAssertNil(f.model.message)
    }
    func testFailedFirstAudioStartDoesNotLatchSelectionAndExplicitRetryWorks() throws {
        var failNext=true
        let f=try fixture(beforeEngineStart:{
            if failNext {failNext=false;throw NSError(domain:"InjectedFirstAudioStart",code:1)}
        });defer{cleanup(f)}
        let firmware=try XCTUnwrap(f.model.selected)
        f.model.selected=nil
        XCTAssertTrue(f.model.load(firmware));idle(f.model,running:false)
        XCTAssertNil(f.model.selected,"A failed candidate must not commit selection")
        XCTAssertNotNil(f.model.message)
        f.model.message=nil
        f.model.sceneChanged(active:false);f.model.sceneChanged(active:true);idle(f.model,running:false)
        XCTAssertNil(f.model.message)
        XCTAssertTrue(f.model.load(firmware));idle(f.model,running:true)
        XCTAssertEqual(f.model.selected,firmware);XCTAssertNil(f.model.message)
    }
    func testSampleAuditionDrainsStopAndPreservesManualPause() async throws {
        let f=try await asyncFixture();addTeardownBlock { @MainActor in await self.cleanupAsync(f) }
        f.model.sceneChanged(active:true);try await settle(f.model,running:true)
        let wanted=await f.model.beginSampleAudition()
        XCTAssertTrue(wanted);XCTAssertFalse(f.model.running);XCTAssertFalse(f.model.busy)
        XCTAssertTrue(f.model.playbackWanted)
        f.model.pause();try await settle(f.model,running:false)
        f.model.endSampleAudition(resume:wanted);try await settle(f.model,running:false)
        XCTAssertFalse(f.model.playbackWanted,"Dismissal must retain a newer explicit pause")
        f.model.resume();try await settle(f.model,running:true)
        let resume=await f.model.beginSampleAudition()
        f.model.endSampleAudition(resume:resume);try await settle(f.model,running:true)
        f.model.pause();try await settle(f.model,running:false)
        let paused=await f.model.beginSampleAudition()
        XCTAssertFalse(paused)
        f.model.endSampleAudition(resume:paused);try await settle(f.model,running:false)
    }
    func testSuccessfulAudioStartActuallyDeliversDeviceCallbacks() async throws {
        let f=try await asyncFixture();addTeardownBlock { @MainActor in await self.cleanupAsync(f) }
        f.model.sceneChanged(active:true);try await settle(f.model,running:true)
        let until=ProcessInfo.processInfo.systemUptime+8
        var output:UInt64=0
        repeat {
            let diagnostics:AudioDiagnostics=await withCheckedContinuation {continuation in
                f.model.captureAudioDiagnostics {continuation.resume(returning:$0)}
            }
            output=diagnostics.outputDeliveredFrames
            if output>0 {break}
            try await Task.sleep(nanoseconds:50_000_000)
        } while ProcessInfo.processInfo.systemUptime<until
        XCTAssertGreaterThan(output,0,"A successful start must produce actual device callbacks, beyond the 1,536-frame prefill")
        XCTAssertNotNil(f.model.screen)
    }
    func testStoppedStartupGraphRebuildsOnceAndDeliversActualCallbacks() async throws {
        var starts=0
        let f=try await asyncFixture(afterEngineStart:{engine in starts += 1;if starts == 1 {engine.stop()}})
        addTeardownBlock { @MainActor in await self.cleanupAsync(f) }
        f.model.sceneChanged(active:true);try await settle(f.model,running:true)
        let until=ProcessInfo.processInfo.systemUptime+8
        var delivered:UInt64=0
        repeat {
            let diagnostic:AudioDiagnostics=await withCheckedContinuation {continuation in
                f.model.captureAudioDiagnostics {continuation.resume(returning:$0)}
            }
            delivered=diagnostic.outputDeliveredFrames
            if starts == 2 && delivered>0 {break}
            try await Task.sleep(nanoseconds:50_000_000)
        } while ProcessInfo.processInfo.systemUptime<until
        XCTAssertEqual(starts,2);XCTAssertGreaterThan(delivered,0)
        XCTAssertNil(f.model.message);XCTAssertTrue(f.model.running)
    }
    func testRepeatedStoppedStartupGraphReportsRetryAndSelectionStillWorks() async throws {
        var stopStarts=true,starts=0
        let f=try await asyncFixture(afterEngineStart:{engine in starts += 1;if stopStarts {engine.stop()}})
        addTeardownBlock { @MainActor in await self.cleanupAsync(f) }
        f.model.sceneChanged(active:true)
        let until=ProcessInfo.processInfo.systemUptime+8
        while f.model.message == nil && ProcessInfo.processInfo.systemUptime<until {try await Task.sleep(nanoseconds:50_000_000)}
        XCTAssertEqual(starts,2,"Recovery must be bounded to one rebuilt graph")
        XCTAssertNotNil(f.model.message);XCTAssertFalse(f.model.running);XCTAssertFalse(f.model.busy)
        stopStarts=false;f.model.message=nil
        XCTAssertTrue(f.model.load(try XCTUnwrap(f.model.selected)))
        try await settle(f.model,running:true)
        XCTAssertEqual(starts,3);XCTAssertNil(f.model.message)
    }
    func testImportedSampleAssignmentSurvivesReloadAndSoundsOnKeyboard() async throws {
        let f=try await asyncFixture();addTeardownBlock { @MainActor in await self.cleanupAsync(f) }
        f.model.sceneChanged(active:true);try await settle(f.model,running:true)
        f.model.pause();try await settle(f.model,running:false)
        let store=ProjectFilesStore(instrument:f.model,directory:f.directory.appendingPathComponent("Projects"))
        let before=try await f.model.captureSloopExportContext().snapshot
        let source=SampleAudioSource(name:"Assignment test",samples:(0..<4410).map {Float(sin(Double($0)*0.13)*0.4)},sourceRate:22050,sourceChannels:1)
        let sample=try SampleAudioImporter.encode(source:source,start:0,end:source.duration)
        try await store.importSample(slotData:sample,slot:1,name:"Assignment test",targetTrack:1)
        var context=try await f.model.captureSloopExportContext()
        XCTAssertEqual(try context.snapshot.bytes("sample1"),sample)
        XCTAssertNotEqual(try context.snapshot.bytes("object0"),try before.bytes("object0"))
        for name in ["sample0","sample2","sample3","arrangement","object2","object3","object4","object5","object6","object7","object8","object9","object10","object11"] {
            XCTAssertEqual(try context.snapshot.bytes(name),try before.bytes(name),name)
        }
        XCTAssertTrue(f.model.load(try XCTUnwrap(f.model.selected)));try await settle(f.model,running:true)
        f.model.pause();try await settle(f.model,running:false)
        context=try await f.model.captureSloopExportContext()
        XCTAssertEqual(try context.snapshot.bytes("sample1"),sample)
        let restored=context
        let peak:Float=try await withCheckedThrowingContinuation {continuation in
            f.worker.async {
                do {
                    let machine=try restored.snapshot.nativeCreate(package:restored.package)
                    defer{instrument_destroy(machine)}
                    var audio=[Float](repeating:0,count:1024),peak:Float=0
                    for _ in 0..<8 {_=instrument_render(machine,&audio,512)}
                    instrument_key(machine,21,true)
                    for _ in 0..<44 {
                        _=instrument_render(machine,&audio,512)
                        peak=max(peak,audio.reduce(0){max($0,abs($1))})
                    }
                    continuation.resume(returning:peak)
                } catch {continuation.resume(throwing:error)}
            }
        }
        XCTAssertGreaterThan(peak,0.001,"The actual imported-and-assigned sound must play after reload")
    }
}
