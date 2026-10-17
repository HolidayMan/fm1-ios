import XCTest
import UIKit
import CryptoKit
@testable import FM1

/// Deltas exclude all startup/warmup counters; ratios use weighted cumulative work.
struct AudioStressWindow: Codable {
    let phase: String
    let elapsedSeconds: Double
    let requestedOutputFrames, deliveredOutputFrames, outputUnderrunFrames, outputUnderrunCallbacks: UInt64
    let renderedCoreFrames, missingCoreFrames, requestedCoreFrames: Int
    let meanRenderRatio, recentP95AtEnd, requestedOutputCoverage: Double
    let zeroShortages, meanMeetsHeadroomTarget, recentP95BelowBudget: Bool

    init(phase: String, start: AudioDiagnostics, end: AudioDiagnostics) throws {
        guard end.elapsedSeconds > start.elapsedSeconds, start.firmware == end.firmware,
              end.outputFrames >= start.outputFrames, end.outputDeliveredFrames >= start.outputDeliveredFrames,
              end.outputUnderrunFrames >= start.outputUnderrunFrames,
              end.outputUnderrunCallbacks >= start.outputUnderrunCallbacks,
              end.renderedFrames >= start.renderedFrames, end.missingFrames >= start.missingFrames else {
            throw NSError(domain:"AudioStress",code:1,userInfo:[NSLocalizedDescriptionKey:"Counters reset or firmware changed inside the stress window"])
        }
        self.phase=phase
        elapsedSeconds=end.elapsedSeconds-start.elapsedSeconds
        requestedOutputFrames=end.outputFrames-start.outputFrames
        deliveredOutputFrames=end.outputDeliveredFrames-start.outputDeliveredFrames
        outputUnderrunFrames=end.outputUnderrunFrames-start.outputUnderrunFrames
        outputUnderrunCallbacks=end.outputUnderrunCallbacks-start.outputUnderrunCallbacks
        renderedCoreFrames=end.renderedFrames-start.renderedFrames
        missingCoreFrames=end.missingFrames-start.missingFrames
        requestedCoreFrames=renderedCoreFrames+missingCoreFrames
        guard requestedCoreFrames > 0 else {
            throw NSError(domain:"AudioStress",code:2,userInfo:[NSLocalizedDescriptionKey:"No core audio was requested inside the stress window"])
        }
        let before=Double(start.renderedFrames+start.missingFrames)
        let after=Double(end.renderedFrames+end.missingFrames)
        meanRenderRatio=(end.renderRatioMean*after-start.renderRatioMean*before)/Double(requestedCoreFrames)
        recentP95AtEnd=end.renderRatioP95 // Recent 256 buffers, not a phase-wide percentile.
        requestedOutputCoverage=Double(requestedOutputFrames)/(elapsedSeconds*end.sampleRate)
        zeroShortages=outputUnderrunFrames == 0 && outputUnderrunCallbacks == 0 && missingCoreFrames == 0
        meanMeetsHeadroomTarget=meanRenderRatio <= 0.8
        recentP95BelowBudget=recentP95AtEnd < 1
    }
}

private struct AudioStressInputEvents:Codable {
    var retriggerCycles=0, keyDownEvents=0, keyUpEvents=0
}

final class AudioStressTests: XCTestCase {
    @MainActor func testStockStress() throws {try measure("stock","Stock-V15")}
    @MainActor func testFeluccaStress() throws {try measure("felucca","Felucca-1.6.1")}
    @MainActor func testSloopStress() throws {try measure("sloop","SLOOP-2.7.1")}

    /// Uses the owner's copied, hash-pinned recording, never an empty demo patch.
    /// The runner must preserve/restore its simulator fixture around this opt-in run.
    @MainActor func testSloopSavedSequencerStress() throws {
        let environment=ProcessInfo.processInfo.environment
        guard environment["FM1_RUN_SAVED_SEQUENCER_STRESS"] == "1" else {
            throw XCTSkip("Saved-loop stress is opt-in: FM1_RUN_SAVED_SEQUENCER_STRESS=1")
        }
        #if DEBUG
        throw XCTSkip("Saved-loop stress requires a Release test build")
        #endif
        let expectedFlash=try XCTUnwrap(environment["FM1_SAVED_SEQUENCER_FLASH_SHA256"],"Runner must pin the copied saved recording")
        let measuredSeconds=Double(environment["FM1_SAVED_SEQUENCER_SECONDS"] ?? "30") ?? 0
        let tempo=Int(environment["FM1_SAVED_SEQUENCER_TEMPO_BPM"] ?? "90") ?? 0
        guard (30...300).contains(measuredSeconds),(20...400).contains(tempo) else {
            XCTFail("Invalid saved-loop duration or fixture tempo metadata");return
        }
        let requireMaxWorkload=environment["FM1_SAVED_SEQUENCER_REQUIRE_MAX_WORKLOAD"] == "1"
        var fixtureDirectory:URL?
        if let relative=environment["FM1_SEQUENCER_FIXTURE_DIRECTORY"] {
            let prefix="Documents/PerformanceFixtures/"
            guard relative.hasPrefix(prefix),relative.count>prefix.count,
                  relative.split(separator:"/").allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else {
                XCTFail("Fixture override must stay under Documents/PerformanceFixtures/<name>");return
            }
            let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].resolvingSymlinksInPath()
            let allowed=documents.appendingPathComponent("PerformanceFixtures",isDirectory:true)
            let candidate=documents.appendingPathComponent(String(relative.dropFirst("Documents/".count)),isDirectory:true).resolvingSymlinksInPath()
            var isDirectory:ObjCBool=false
            guard candidate.path.hasPrefix(allowed.path+"/"),
                  FileManager.default.fileExists(atPath:candidate.path,isDirectory:&isDirectory),isDirectory.boolValue else {
                XCTFail("Isolated fixture directory must exist inside Documents/PerformanceFixtures");return
            }
            fixtureDirectory=candidate
        }
        let preferenceSuite="FM1SequencerFixture.\(UUID().uuidString)"
        let preferences=try XCTUnwrap(UserDefaults(suiteName:preferenceSuite))
        let previousIdlePolicy=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        let instrument=Instrument(directory:fixtureDirectory,preferences:preferences)
        let playKey=12, padKey=14
        var sequencerStarted=false
        defer {
            instrument.key(padKey,false)
            if sequencerStarted {instrument.key(playKey,true);instrument.key(playKey,false)}
            instrument.pause()
            let stopped=expectation(description:"Saved sequencer checkpoint finished")
            instrument.captureAudioDiagnostics {_ in stopped.fulfill()}
            wait(for:[stopped],timeout:10)
            UIApplication.shared.isIdleTimerDisabled=previousIdlePolicy
            preferences.removePersistentDomain(forName:preferenceSuite)
        }
        let firmware=try XCTUnwrap(instrument.firmwares.first {$0.name == "SLOOP-2.7.1"})
        let pinned=try XCTUnwrap(CatalogFirmware.bundled.first {$0.id == "sloop"})
        func sha(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        let digest=sha(try Data(contentsOf:firmware.url))
        XCTAssertEqual(digest,pinned.sha256)
        guard digest == pinned.sha256 else {return}
        let flashURL=firmware.url.deletingPathExtension().appendingPathExtension("flash")
        let initialFlash=sha(try Data(contentsOf:flashURL))
        XCTAssertEqual(initialFlash,expectedFlash,"Must use the runner's exact saved sequencer fixture")
        guard initialFlash == expectedFlash else {return}
        instrument.load(firmware)
        let boot=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in instrument.running && !instrument.busy},object:nil)
        guard XCTWaiter.wait(for:[boot],timeout:20) == .completed else {XCTFail("Saved SLOOP did not start");return}
        XCTAssertEqual(preferences.string(forKey:FirmwareSelection.preferenceKey),firmware.id,"Successful loading must persist the exact installed identity")
        hold(5)
        let warmupEnd=try capture(instrument)
        XCTAssertEqual(warmupEnd.backend,.native)
        guard warmupEnd.backend == .native else {return}
        instrument.key(playKey,true);hold(0.05);instrument.key(playKey,false)
        sequencerStarted=true
        let playingStart=try capture(instrument)
        hold(measuredSeconds-15)
        let loopOnlyEnd=try capture(instrument)
        var input=AudioStressInputEvents(), padDown=false
        var pendingRelease:DispatchWorkItem?
        let attacks=Timer(timeInterval:0.125,repeats:true) {_ in
            instrument.key(padKey,true);padDown=true
            input.keyDownEvents += 1;input.retriggerCycles += 1
            let release=DispatchWorkItem {
                instrument.key(padKey,false);padDown=false;input.keyUpEvents += 1
            }
            pendingRelease=release
            DispatchQueue.main.asyncAfter(deadline:.now()+0.08,execute:release)
        }
        RunLoop.main.add(attacks,forMode:.common);attacks.fire()
        hold(15)
        attacks.invalidate();pendingRelease?.cancel()
        if padDown {instrument.key(padKey,false);input.keyUpEvents += 1}
        let steadyEnd=try capture(instrument)
        // STOP is the same hardware transport toggle, held long enough for a scan.
        instrument.key(playKey,true);hold(0.05);instrument.key(playKey,false)
        sequencerStarted=false
        let phases=[try AudioStressWindow(phase:"saved-sequencer",start:playingStart,end:loopOnlyEnd),
                    try AudioStressWindow(phase:"saved-sequencer-same-pad-8Hz",start:loopOnlyEnd,end:steadyEnd)]
        let steady=try AudioStressWindow(phase:"saved-sequencer-total",start:playingStart,end:steadyEnd)
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:encoder.encode(value))}
        #if targetEnvironment(simulator)
        let platform="iOS Simulator"
        #else
        let platform="iOS device"
        #endif
        let report:[String:Any]=[
            "benchmarkPlatform":platform,"benchmarkConfiguration":"Release","usesIsolatedFixtureDirectory":fixtureDirectory != nil,
            "benchmarkRevision":environment["FM1_BENCHMARK_REVISION"] ?? "unspecified",
            "benchmarkRun":environment["FM1_BENCHMARK_RUN"] ?? "unspecified",
            "firmware":firmware.id,"benchmarkFirmwareSHA256":digest,"benchmarkInitialFlashSHA256":initialFlash,
            "savedPatternTempoBPM":tempo,"warmupSeconds":5,"measuredSeconds":measuredSeconds,"playMatrixID":playKey,
            "retriggerMatrixID":padKey,"retriggerSeconds":0.125,"retriggerHoldSeconds":0.08,
            "inputEvents":try object(input),"meanRenderTarget":0.2,
            "warmupEnd":try object(warmupEnd),"steadyEnd":try object(steadyEnd),
            "phases":try object(phases),"steadyWindow":try object(steady),
            "meanMeetsNativeTarget":steady.meanRenderRatio<0.2,"requiresMaxWorkload":requireMaxWorkload]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:instrument.directory.deletingLastPathComponent().appendingPathComponent("Stress-sloop-saved-sequencer.json"),options:.atomic)
        print("SAVED SEQUENCER STRESS \(platform): \(String(decoding:data,as:UTF8.self))")
        XCTAssertEqual(steadyEnd.backend,.native)
        let playingBefore=try XCTUnwrap(playingStart.nativeWorkload)
        let playingAfter=try XCTUnwrap(steadyEnd.nativeWorkload)
        let loopAfter=try XCTUnwrap(loopOnlyEnd.nativeWorkload)
        XCTAssertEqual(playingAfter.droppedKeyTransitions,0,"Bounded native input queue must not lose transitions")
        XCTAssertGreaterThan(loopAfter.nonzeroDSPSamples,playingBefore.nonzeroDSPSamples,"Recorded loop must produce audio before live pad attacks")
        XCTAssertGreaterThanOrEqual(playingAfter.framesWhilePlaying,playingBefore.framesWhilePlaying,"Native workload counters must not reset")
        let playingFrames=playingAfter.framesWhilePlaying >= playingBefore.framesWhilePlaying ? playingAfter.framesWhilePlaying-playingBefore.framesWhilePlaying : 0
        XCTAssertGreaterThanOrEqual(Double(playingFrames),steady.elapsedSeconds*steadyEnd.sampleRate*0.9,"Transport must actually play the saved sequence")
        if requireMaxWorkload {
            XCTAssertEqual(playingAfter.activeTrackMask,15,"All four tracks must be active")
            XCTAssertGreaterThanOrEqual(playingAfter.peakSharedSynthVoices,8,"Shared synth pool must reach its eight-voice budget")
            XCTAssertGreaterThanOrEqual(playingAfter.peakDrumVoices,6,"All six drum voices must overlap")
            XCTAssertEqual(playingAfter.configuredEffectMask & 2047,2047,"Every supported effect configuration must be exercised")
        }
        XCTAssertTrue(instrument.running)
        XCTAssertGreaterThanOrEqual(steady.elapsedSeconds,measuredSeconds)
        XCTAssertGreaterThanOrEqual(input.retriggerCycles,100,"At least 100 of the nominal 120 pad attacks must arrive")
        XCTAssertEqual(input.keyDownEvents,input.keyUpEvents)
        for window in phases {
            XCTAssertTrue(window.zeroShortages,"\(window.phase): saved-loop core/output shortage")
            XCTAssertGreaterThanOrEqual(window.requestedOutputCoverage,0.9,"Output callbacks must cover the measured clock")
            XCTAssertLessThan(window.meanRenderRatio,0.2,"Native saved-loop render must retain 80% mean CPU headroom")
        }
    }

    @MainActor private func capture(_ instrument: Instrument) throws -> AudioDiagnostics {
        var value:AudioDiagnostics?
        let captured=expectation(description:"Worker diagnostics boundary")
        instrument.captureAudioDiagnostics {report in value=report;captured.fulfill()}
        wait(for:[captured],timeout:10)
        return try XCTUnwrap(value)
    }
    @MainActor private func hold(_ seconds:Double) {
        let held=expectation(description:"Sustained audio \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline:.now()+seconds){held.fulfill()}
        wait(for:[held],timeout:seconds+10)
    }
    @MainActor private func holdWithAttacks(_ seconds:Double,keys:[Int],instrument:Instrument) -> AudioStressInputEvents {
        var events=AudioStressInputEvents(), released=false
        var pendingAttack:DispatchWorkItem?
        let retrigger=Timer(timeInterval:1,repeats:true) {_ in
            for key in keys {instrument.key(key,false)}
            events.keyUpEvents += keys.count;released=true;events.retriggerCycles += 1
            let attack=DispatchWorkItem {
                for key in keys {instrument.key(key,true)}
                events.keyDownEvents += keys.count;released=false
            }
            pendingAttack=attack
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05,execute:attack)
        }
        RunLoop.main.add(retrigger,forMode:.common)
        hold(seconds)
        retrigger.invalidate();pendingAttack?.cancel()
        if released {
            for key in keys {instrument.key(key,true)}
            events.keyDownEvents += keys.count
        }
        return events
    }
    @MainActor private func measure(_ key:String,_ name:String) throws {
        let environment=ProcessInfo.processInfo.environment
        guard environment["FM1_RUN_AUDIO_STRESS"] == "1" else {
            throw XCTSkip("Audio stress is opt-in: FM1_RUN_AUDIO_STRESS=1")
        }
        #if DEBUG
        throw XCTSkip("Audio stress requires a Release test build")
        #endif
        let previousIdlePolicy=UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled=true
        let instrument=Instrument()
        var timer:Timer?
        defer {
            timer?.invalidate()
            for key in [21,25,28] {instrument.key(key,false)}
            instrument.pause()
            // Drain pause/checkpoint before another test touches the shared audio session.
            let stopped=expectation(description:"Stress audio session stopped")
            instrument.captureAudioDiagnostics {_ in stopped.fulfill()}
            wait(for:[stopped],timeout:10)
            UIApplication.shared.isIdleTimerDisabled=previousIdlePolicy
        }
        let firmware=try XCTUnwrap(instrument.firmwares.first {$0.name == name || $0.name.hasPrefix(name+" · ")})
        let pinned=try XCTUnwrap(CatalogFirmware.bundled.first {$0.id == key})
        let digest=SHA256.hash(data:try Data(contentsOf:firmware.url)).map {String(format:"%02x",$0)}.joined()
        guard digest == pinned.sha256 else {XCTFail("Stress firmware does not match the pinned release");return}
        let flashURL=firmware.url.deletingPathExtension().appendingPathExtension("flash")
        let initialFlash=(try? Data(contentsOf:flashURL)).map {SHA256.hash(data:$0).map {String(format:"%02x",$0)}.joined()} ?? "absent"
        instrument.load(firmware)
        let boot=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in instrument.running && !instrument.busy && instrument.selected?.id == firmware.id},object:nil)
        guard XCTWaiter.wait(for:[boot],timeout:20) == .completed else {XCTFail("Stress firmware did not start");return}
        instrument.key(21,true)
        hold(5)
        let warmupEnd=try capture(instrument)
        XCTAssertTrue(instrument.running)
        let singleInputs=holdWithAttacks(20,keys:[21],instrument:instrument)
        let singleEnd=try capture(instrument)
        XCTAssertTrue(instrument.running)
        instrument.key(25,true);instrument.key(28,true)
        let chordInputs=holdWithAttacks(20,keys:[21,25,28],instrument:instrument)
        let chordEnd=try capture(instrument)
        XCTAssertTrue(instrument.running)
        var nextDelta=1, encoderBalance=0, encoderEvents=0
        timer=Timer(timeInterval:0.125,repeats:true) {_ in
            instrument.encoder(2,nextDelta)
            encoderBalance += nextDelta;encoderEvents += 1;nextDelta = -nextDelta
        }
        RunLoop.main.add(timer!,forMode:.common)
        let controlInputs=holdWithAttacks(20,keys:[21,25,28],instrument:instrument)
        timer?.invalidate();timer=nil
        if encoderBalance != 0 {instrument.encoder(2,-encoderBalance);encoderEvents += 1}
        let steadyEnd=try capture(instrument)
        XCTAssertTrue(instrument.running)
        let phases=[try AudioStressWindow(phase:"matrix21-repeated",start:warmupEnd,end:singleEnd),
                    try AudioStressWindow(phase:"matrix21-25-28-repeated",start:singleEnd,end:chordEnd),
                    try AudioStressWindow(phase:"matrix21-25-28-repeated-with-encoder",start:chordEnd,end:steadyEnd)]
        let steady=try AudioStressWindow(phase:"steady-total",start:warmupEnd,end:steadyEnd)
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        func object<T:Encodable>(_ value:T) throws -> Any {try JSONSerialization.jsonObject(with:encoder.encode(value))}
        #if targetEnvironment(simulator)
        let platform="iOS Simulator"
        #else
        let platform="iOS device"
        #endif
        let report:[String:Any]=[
            "benchmarkPlatform":platform,"benchmarkDeviceName":environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model,
            "benchmarkModelIdentifier":environment["SIMULATOR_MODEL_IDENTIFIER"] ?? steadyEnd.device,
            "benchmarkConfiguration":"Release","benchmarkRevision":environment["FM1_BENCHMARK_REVISION"] ?? "unspecified",
            "benchmarkRun":environment["FM1_BENCHMARK_RUN"] ?? "unspecified","firmware":firmware.id,
            "benchmarkFirmwareSHA256":digest,"benchmarkInitialFlashSHA256":initialFlash,
            "warmupSeconds":5,"measuredSeconds":60,"matrixWorkloadKeys":[21,25,28],"encoderID":2,
            "retriggerSeconds":1,"retriggerReleaseGapSeconds":0.05,
            "phaseInputEvents":try object([singleInputs,chordInputs,controlInputs]),
            "keyDownEvents":singleInputs.keyDownEvents+chordInputs.keyDownEvents+controlInputs.keyDownEvents,
            "keyUpEvents":singleInputs.keyUpEvents+chordInputs.keyUpEvents+controlInputs.keyUpEvents,
            "encoderPairSeconds":0.25,"encoderEvents":encoderEvents,"meanHeadroomTarget":0.8,
            "warmupEnd":try object(warmupEnd),"steadyEnd":try object(steadyEnd),
            "steadyWindow":try object(steady),"phases":try object(phases)]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:instrument.directory.deletingLastPathComponent().appendingPathComponent("Stress-\(key).json"),options:.atomic)
        print("AUDIO STRESS \(platform) \(key): \(String(decoding:data,as:UTF8.self))")
        // Write reports before gates so a failing candidate still leaves usable evidence.
        XCTAssertGreaterThanOrEqual(steady.elapsedSeconds,60)
        XCTAssertGreaterThanOrEqual(encoderEvents,120,"Control phase must deliver at least 75% of the nominal 160 encoder events")
        for events in [singleInputs,chordInputs,controlInputs] {
            XCTAssertGreaterThanOrEqual(events.retriggerCycles,15,"Each phase must deliver at least 75% of nominal note retriggers")
            XCTAssertEqual(events.keyDownEvents,events.keyUpEvents,"Every measured release must have a matching attack before capture")
        }
        for window in phases {
            XCTAssertTrue(window.zeroShortages,"\(window.phase): steady output/core shortage")
            XCTAssertGreaterThan(window.requestedOutputCoverage,0.9,"\(window.phase): output callbacks did not cover the measured time")
        }
        // mean <=0.8 and recent p95 <1 are explicit report flags, separate from shortage gates.
    }
}

final class AudioStressWindowTests:XCTestCase {
    func testWeightedDeltaExcludesWarmupCounters() throws {
        var start=AudioDiagnostics();start.firmware="test";start.elapsedSeconds=5
        start.renderedFrames=900;start.missingFrames=100;start.renderRatioMean=1.2
        start.outputFrames=1000;start.outputDeliveredFrames=800;start.outputUnderrunFrames=200;start.outputUnderrunCallbacks=2
        var end=start;end.elapsedSeconds=65;end.renderedFrames=9900;end.renderRatioMean=0.7;end.renderRatioP95=0.9
        end.outputFrames += 60*44100;end.outputDeliveredFrames += 60*44100
        let result=try AudioStressWindow(phase:"steady",start:start,end:end)
        XCTAssertEqual(result.meanRenderRatio,(0.7*10000-1.2*1000)/9000,accuracy:0.000001)
        XCTAssertEqual(result.missingCoreFrames,0);XCTAssertEqual(result.outputUnderrunFrames,0)
        XCTAssertTrue(result.zeroShortages);XCTAssertTrue(result.meanMeetsHeadroomTarget);XCTAssertTrue(result.recentP95BelowBudget)
        XCTAssertEqual(result.requestedOutputCoverage,1,accuracy:0.000001)
    }
    func testCounterResetIsRejected() {
        var start=AudioDiagnostics();start.elapsedSeconds=5;start.outputFrames=100
        var end=start;end.elapsedSeconds=65;end.outputFrames=99
        XCTAssertThrowsError(try AudioStressWindow(phase:"steady",start:start,end:end))
    }
}
