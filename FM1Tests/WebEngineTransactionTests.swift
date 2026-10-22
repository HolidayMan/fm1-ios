#if FM1_RESEARCH
import XCTest
import WebKit
@testable import FM1

private final class FakeWebEngine:WebEngineHosting {
    let identity=UUID()
    var presentationView:WKWebView? {nil}
    var onSnapshot:(([String:Any])->Void)?
    var onDiagnostics:(([String:Any])->Void)?
    var onCheckpoint:((Data)->Void)?
    var onFailure:((Error)->Void)?
    private let lock=NSLock()
    private var current=Data(),nextPause:Data?,pauseFailure=false
    private(set) var closed=false
    private(set) var loadedMHz=240
    func load(package:Data,flash:Data?,moduleSHA256:String)throws {lock.lock();current=flash ?? Data(repeating:0xff,count:1<<20);lock.unlock()}
    func load(package:Data,flash:Data?,moduleSHA256:String,guestMHz:Int)throws {try load(package:package,flash:flash,moduleSHA256:moduleSHA256);loadedMHz=guestMHz}
    func command(_ op:String,values:[String:Any],timeout:TimeInterval)throws->[String:Any] {
        lock.lock();defer{lock.unlock()}
        if op == "flash" {return ["flash":current.base64EncodedString()]}
        return [:]
    }
    func startCheckpoints() {}
    func pause()throws->Data {
        lock.lock();defer{lock.unlock()}
        if pauseFailure {throw NSError(domain:"FakeWK",code:1,userInfo:[NSLocalizedDescriptionKey:"The content process stopped; its previous checkpoint is retained."])}
        if let nextPause {current=nextPause;self.nextPause=nil}
        return current
    }
    func changeAtNextPause(_ bytes:Data) {lock.lock();nextPause=bytes;lock.unlock()}
    func failPause() {lock.lock();pauseFailure=true;lock.unlock()}
    func close() {closed=true}
}
private final class FakeWebFactory {
    private let lock=NSLock()
    private var engines:[FakeWebEngine]=[]
    let first=FakeWebEngine()
    func make()->FakeWebEngine {
        lock.lock();defer{lock.unlock()}
        let engine=engines.isEmpty ? first : FakeWebEngine();engines.append(engine);return engine
    }
    var latest:FakeWebEngine {lock.lock();defer{lock.unlock()};return engines.last ?? first}
    var count:Int {lock.lock();defer{lock.unlock()};return engines.count}
}
private final class StartFailureGate {
    private let lock=NSLock();private var next=false
    func arm() {lock.lock();next=true;lock.unlock()}
    func check()throws {lock.lock();let fail=next;next=false;lock.unlock();if fail {throw NSError(domain:"TestStart",code:1,userInfo:[NSLocalizedDescriptionKey:"Injected candidate audio start failure"])} }
}

@MainActor final class WebEngineTransactionTests:XCTestCase {
    private struct Fixture {
        let model:Instrument,web:FakeWebEngine,factory:FakeWebFactory,gate:StartFailureGate,directory:URL,preferences:UserDefaults,suite:String,native:Data
        var nativeURL:URL {directory.appendingPathComponent("SLOOP-2.7.1.flash")}
        var wasmURL:URL {directory.appendingPathComponent("SLOOP-2.7.1.wasm.flash")}
    }
    private func fixture()throws->Fixture {
        let source=Instrument()
        guard let firmware=source.firmwares.first(where:{$0.name == "SLOOP-2.7.1"}) else {throw XCTSkip("Requires the dedicated installed SLOOP package; never downloads")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let bytes=try Data(contentsOf:firmware.url)
        try bytes.write(to:directory.appendingPathComponent("SLOOP-2.7.1.fwsc"))
        var error=[UInt8](repeating:0,count:512)
        guard let machine=bytes.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress,bytes.count,&error,error.count)}) else {throw NSError(domain:"Fixture",code:1)}
        var native=Data(count:1<<20)
        native.withUnsafeMutableBytes {_=instrument_flash(machine,$0.bindMemory(to:UInt8.self).baseAddress,1<<20)}
        instrument_destroy(machine)
        try native.write(to:directory.appendingPathComponent("SLOOP-2.7.1.flash"))
        let suite="WebTransactionTests.\(UUID().uuidString)",preferences=UserDefaults(suiteName:suite)!
        preferences.set("wasm",forKey:SloopExecutionMode.preferenceKey)
        let factory=FakeWebFactory(),gate=StartFailureGate()
        let model=Instrument(directory:directory,preferences:preferences,webEngineFactory:{factory.make()},beforeEngineStart:{try gate.check()})
        return Fixture(model:model,web:factory.first,factory:factory,gate:gate,directory:directory,preferences:preferences,suite:suite,native:native)
    }
    private func settle(_ model:Instrument,running:Bool,file:StaticString=#filePath,line:UInt=#line) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in !model.busy && model.running == running},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:15),.completed,"\(model.message ?? model.status)",file:file,line:line)
    }
    private func cleanup(_ f:Fixture) {f.model.pause();settle(f.model,running:false);f.web.close();f.preferences.removePersistentDomain(forName:f.suite);try? FileManager.default.removeItem(at:f.directory)}
    func testFailedCandidateStartRetainsLatestOutgoingWASMCheckpoint()throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);settle(f.model,running:true)
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),f.native)
        var newest=f.native;newest[0x80000] ^= 0x01
        f.web.changeAtNextPause(newest)
        f.gate.arm();f.model.setExecutionMode(.native);settle(f.model,running:false)
        XCTAssertEqual(f.model.executionMode,.wasm,"A failed candidate does not commit its mode")
        XCTAssertEqual(f.preferences.string(forKey:SloopExecutionMode.preferenceKey),"wasm")
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),newest,"Rollback must use the post-pause snapshot, never its stale pre-pause cache")
        XCTAssertEqual(try Data(contentsOf:f.nativeURL),f.native)
        XCTAssertTrue(f.model.message?.contains("Injected candidate") == true)
    }
    func testDeadWASMCanReturnToNativeWithoutOverwritingLastCheckpoint()throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);settle(f.model,running:true)
        let saved=try Data(contentsOf:f.wasmURL)
        f.web.failPause();f.model.pause();settle(f.model,running:false)
        XCTAssertTrue(f.web.closed)
        XCTAssertNotNil(f.model.message)
        f.model.message=nil;f.model.setExecutionMode(.native);settle(f.model,running:false)
        XCTAssertEqual(f.model.executionMode,.native)
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),saved)
        XCTAssertEqual(try Data(contentsOf:f.nativeURL),f.native)
        XCTAssertFalse(f.model.playbackWanted)
    }
    func testInvalidDestinationSaveRetainsPriorModeAndBothFiles()throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);settle(f.model,running:true)
        let broken=Data([1,2,3]);try broken.write(to:f.nativeURL)
        f.model.setExecutionMode(.native);settle(f.model,running:false)
        XCTAssertEqual(f.model.executionMode,.wasm)
        XCTAssertEqual(try Data(contentsOf:f.nativeURL),broken,"Invalid data is diagnosed, never replaced silently")
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),f.native)
        XCTAssertNotNil(f.model.message)
    }
    func testClockChangePreservesPausedIntentAndLatestSavedProject()throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);settle(f.model,running:true)
        var latest=f.native;latest[0x80000] ^= 1;f.web.changeAtNextPause(latest)
        f.model.pause();settle(f.model,running:false)
        f.model.setEmulatorMHz(180);settle(f.model,running:false)
        XCTAssertEqual(f.model.emulatorMHz,180)
        XCTAssertEqual(f.preferences.integer(forKey:EmulatorClock.preferenceKey),180)
        XCTAssertEqual(f.factory.latest.loadedMHz,180)
        XCTAssertFalse(f.model.playbackWanted)
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),latest)
        XCTAssertEqual(try Data(contentsOf:f.nativeURL),f.native)
        let count=f.factory.count;f.model.setEmulatorMHz(999)
        XCTAssertEqual(f.factory.count,count);XCTAssertEqual(f.model.emulatorMHz,180)
    }
    func testFailedClockRestartDoesNotCommitPreferenceOrDiscardCheckpoint()throws {
        let f=try fixture();defer{cleanup(f)}
        f.model.sceneChanged(active:true);settle(f.model,running:true)
        var latest=f.native;latest[0x80000] ^= 1;f.web.changeAtNextPause(latest)
        f.gate.arm();f.model.setEmulatorMHz(360);settle(f.model,running:false)
        XCTAssertEqual(f.model.emulatorMHz,240)
        XCTAssertEqual(f.preferences.integer(forKey:EmulatorClock.preferenceKey),240)
        XCTAssertEqual(f.model.executionMode,.wasm)
        XCTAssertEqual(try Data(contentsOf:f.wasmURL),latest)
        XCTAssertEqual(try Data(contentsOf:f.nativeURL),f.native)
    }
}

#endif
