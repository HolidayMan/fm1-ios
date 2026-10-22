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
    private func fixture(valid:Bool=true)throws->Fixture {
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
        let model=Instrument(directory:directory,preferences:preferences,worker:worker,nativeOnly:true)
        let scanned=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in model.selected != nil},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[scanned],timeout:15),.completed)
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
}
