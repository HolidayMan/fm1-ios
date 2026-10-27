import SwiftUI
import AVFoundation
import CryptoKit
import Darwin
#if FM1_RESEARCH
import WebKit
#endif

struct Firmware: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

/// In-memory authorization for one checked, app-owned saved-data recovery copy.
/// It deliberately cannot be reconstructed from an arbitrary Files URL.
struct FirmwareResetRecovery:Sendable,Identifiable,Equatable {
    let id:UUID
    let firmwareID:String
    let packageSHA256:String
    let backupURL:URL
    fileprivate let receiptSHA256:String
}

private struct FirmwareResetReceipt:Codable {
    let schemaVersion:Int
    let id:UUID
    let firmwareID:String
    let firmwareName:String
    let packageSHA256:String
    let packageVersion:String
    let nativeKind:UInt32
    let originalSHA256:String
    let originalBytes:Int
    let autosaveFilename:String
    let createdAt:Date
}

/// All emulator state belongs to the worker queue. The source-node callback only
/// reads already-produced samples and signals a coalesced refill; it never emulates.
final class Instrument: ObservableObject {
    @Published var firmwares: [Firmware] = []
    @Published var selected: Firmware?
    @Published var running = false
    @Published var busy = false
    @Published private(set) var playbackWanted = false
    @Published var message: String?
    let displayState=InstrumentDisplayState()
    var screen:CGImage? {get {displayState.screen} set {displayState.screen=newValue}}
    var leds:[Float] {get {displayState.leds} set {if newValue != displayState.leds {displayState.leds=newValue}}}
    @Published var status = "Choose a firmware to begin"
    @Published var muted = false
    @Published var volume: Double = 0.7
    @Published private(set) var audioDiagnostics = AudioDiagnostics()
    @Published private(set) var executionMode:SloopExecutionMode = .native
    @Published private(set) var supportsExperimentalWASM=false
#if FM1_RESEARCH
    @Published private(set) var experimentalWebView:WKWebView?
#endif
    @Published private(set) var emulatorMHz=EmulatorClock.defaultMHz
    /// File formats are implemented only for the pinned native SLOOP backend.
    var supportsProjectFiles:Bool {nativeBackendName == "SLOOP" && executionMode == .native}
    @Published private(set) var nativeBackendName:String?
    var supportsClockControl:Bool {selected != nil && executionMode == .wasm}
    private let worker: DispatchQueue
    private var machine: UnsafeMutableRawPointer?
#if FM1_RESEARCH
    private var webEngine:WebEngineHosting?
    private var webFlash:Data?
    private var webPauseError:Error?
    private var webUnrecoverable=false
    private var displayedWebIdentity:UUID? // Main-thread UI identity only.
    private var webDiagnostics=AudioDiagnostics()
#endif
    private var activeMode:SloopExecutionMode = .native
    private var activeNativeKind:UInt32=0
    private var activeGuestMHz=EmulatorClock.defaultMHz
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var audioRing: AudioRing?
    private var refillSignal: DispatchSourceUserDataAdd?
    private var producerScheduled = false
    private var generation = 0
    private var playing = false
    private var activeID: String?
    private var nativeReplacementUncommitted=false // Worker only: candidate cannot checkpoint before its sole commit.
    private var lastSnapshot = CFAbsoluteTimeGetCurrent()
    private var lastSave = CFAbsoluteTimeGetCurrent()
    private static let framesPerBuffer = 512
    private static let targetBufferedFrames = 1536 // 35 ms target; never an unbounded audio queue.
    private static let ringCapacity = 2048 // 46 ms hard maximum.
    private var health = AudioHealth()
    private var gapSmoother = AudioGapSmoother()
    private var playbackStart: TimeInterval = 0
    private var lastDiagnostics: TimeInterval = 0
    // Hashing and atomic disk writes must not compete with interpreter deadlines.
    private let storage = DispatchQueue(label: "fm1.storage", qos: .utility)
    private var flashDigests: [String: Data] = [:] // Storage queue only.
    private var workerMuted = false
    private var workerVolume: UInt32 = 716
    private var pixels = [UInt32](repeating: 0, count: 240*240)
    private var lights = [Float](repeating: 0, count: 41)
    private var samples = [Float](repeating: 0, count: 1024)
    private var observations: [NSObjectProtocol] = []
    let directory: URL
    private let preferences: UserDefaults
    let nativeOnly:Bool
#if FM1_RESEARCH
    private var webEngineFactory:() throws -> WebEngineHosting = {try WebInstrumentEngine.make()}
    convenience init(directory:URL?=nil,preferences:UserDefaults = .standard,worker:DispatchQueue?=nil,webEngineFactory:@escaping () throws -> WebEngineHosting,beforeEngineStart:(() throws -> Void)?=nil,nativeOnly:Bool=false) {
        self.init(directory:directory,preferences:preferences,worker:worker,beforeEngineStart:beforeEngineStart,nativeOnly:nativeOnly)
        self.webEngineFactory=webEngineFactory
    }
#endif
    private let beforeEngineStart:(() throws -> Void)?
    private let afterEngineStart:((AVAudioEngine)->Void)?
    private var restoredSelectionNeedsLoad = false
    // Main-thread policy and operation receipts; machine state stays on worker.
    private var playbackPolicy=PlaybackPolicy()
    private let playbackDemand=PlaybackDemand()
    private var playbackTicket=0
    private var workerPlaybackEpoch=0 // Worker only: explicit Play that started this engine.
    private var sampleAuditionDepth=0
    private var firmwareLoadPending=false, importPending=false
    init(directory: URL? = nil, preferences: UserDefaults = .standard, worker:DispatchQueue? = nil,beforeEngineStart:(() throws -> Void)? = nil,afterEngineStart:((AVAudioEngine)->Void)?=nil,nativeOnly:Bool=false) {
#if FM1_RESEARCH
        self.nativeOnly=nativeOnly
#else
        precondition(!instrument_research_enabled(),"Store builds require the native-only core.")
        self.nativeOnly=true
        let nativeOnly=true
#endif
        self.beforeEngineStart=beforeEngineStart
        self.afterEngineStart=afterEngineStart
        self.worker=worker ?? DispatchQueue(label:"fm1.instrument",qos:.userInteractive)
        self.preferences = preferences
        emulatorMHz=EmulatorClock.validated(preferences.integer(forKey:EmulatorClock.preferenceKey))
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Firmwares", isDirectory: true)
        do { try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true) }
        catch { message = error.localizedDescription }
        firmwares=nativeOnly ? [] : Self.scanFirmwares(in:self.directory)
        selected = FirmwareSelection.preferred(in: firmwares, lastID: preferences.string(forKey: FirmwareSelection.preferenceKey))
        executionMode=nativeOnly ? .native : (SloopExecutionMode(rawValue:preferences.string(forKey:SloopExecutionMode.preferenceKey) ?? "") ?? .native)
        // Package probing belongs to the serial loader, not view construction.
        restoredSelectionNeedsLoad = selected != nil
        if selected != nil {status = "Paused · tap Resume"}
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type=AVAudioSession.InterruptionType(rawValue:raw) else{return}
            if type == .began {self?.interruptionBegan()}
            else {
                let options=AVAudioSession.InterruptionOptions(rawValue:note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                self?.interruptionEnded(shouldResume:options.contains(.shouldResume))
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { self?.outputDisconnected() }
        })
        observations.append(NotificationCenter.default.addObserver(forName:AVAudioSession.mediaServicesWereResetNotification,object:nil,queue:.main) { [weak self] _ in
            // The OS invalidates audio objects on media-service reset. Rebuild
            // through the same serial stop/start path, retaining user intent.
            self?.queuePlayback(forceCheckpoint:true)
        })
        if nativeOnly {refresh()}
    }
    func refresh() {
        let directory=directory,nativeOnly=nativeOnly
        storage.async { [weak self] in
            let scanned=Self.scanFirmwares(in:directory,nativeOnly:nativeOnly)
            DispatchQueue.main.async {
                guard let self else{return}
                if self.firmwares != scanned {self.firmwares=scanned}
                // First native-only launch resolves exact package hashes off main.
                // A remembered unsupported package stays on disk but cannot run.
                if self.nativeOnly,self.selected == nil,!self.firmwareLoadPending,!self.importPending {
                    self.selected=FirmwareSelection.preferred(in:scanned,lastID:self.preferences.string(forKey:FirmwareSelection.preferenceKey))
                    self.restoredSelectionNeedsLoad=self.selected != nil
                    if self.selected != nil {
                        self.status="Paused · tap Resume"
                        if self.playbackPolicy.shouldRun {self.requestPlayback()}
                    }
                }
            }
        }
    }
    private static func scanFirmwares(in directory:URL,nativeOnly:Bool=false)->[Firmware] {
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        return files.filter {
            guard $0.pathExtension.lowercased() == "fwsc" else{return false}
            guard nativeOnly else{return true}
            guard let size=try? $0.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                  (960...4*1024*1024).contains(size),let data=try? Data(contentsOf:$0) else{return false}
            return nativeKind(data) != 0
        }.map {
            Firmware(id: $0.deletingPathExtension().lastPathComponent, name: $0.deletingPathExtension().lastPathComponent.components(separatedBy: " · ").first ?? $0.deletingPathExtension().lastPathComponent, url: $0)
        }.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    private static func nativeKind(_ data:Data)->UInt32 {
        data.withUnsafeBytes {instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,data.count)}
    }
    func importFirmware(_ url: URL, removeAfterImport: Bool = false) {
        guard !busy else{return}
        playbackPolicy.play();playbackDemand.clearFailure();updatePlaybackDemand()
        importPending=true
        let ticket=beginPlaybackOperation(),epoch=playbackDemand.epoch
        worker.async { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                if removeAfterImport { try? FileManager.default.removeItem(at: url) }
            }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size >= 960 && size <= 4*1024*1024 else { throw failure("Choose an FM-1 .fwsc package smaller than 4 MB.") }
                let data = try Data(contentsOf: url)
                guard !nativeOnly || Self.nativeKind(data) != 0 else {throw failure("This instrument is not included in this version of the app.")}
                var err = [UInt8](repeating: 0, count: 512)
                guard let candidate = data.withUnsafeBytes({ instrument_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &err, err.count) }) else {
                    throw failure(String(cString: err.map { CChar(bitPattern: $0) }))
                }
                instrument_destroy(candidate)
                // Identical imports reuse a file; a different version never overwrites its predecessor.
                let fullDigest = SHA256.hash(data: data)
                let digest = fullDigest.prefix(4).map {String(format:"%02x",$0)}.joined()
                let name = String(url.deletingPathExtension().lastPathComponent.prefix(64)) + " · " + digest
                // Reuse the same binary even when it was originally installed under a
                // different filename; downloading it again must not fork its saved sounds.
                let existing = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
                    .filter { $0.pathExtension.lowercased() == "fwsc" }
                    .sorted { a,b in
                        let rank: (URL) -> Int = { candidate in
                            let id = candidate.deletingPathExtension().lastPathComponent
                            return id == self.activeID ? 0 : (id.contains(" · ") ? 2 : 1)
                        }
                        return rank(a) == rank(b) ? a.lastPathComponent < b.lastPathComponent : rank(a) < rank(b)
                    }.first { candidate in
                        guard (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) == data.count,
                              let bytes = try? Data(contentsOf: candidate) else {return false}
                        return SHA256.hash(data: bytes) == fullDigest
                    }
                let dest = existing ?? directory.appendingPathComponent(name).appendingPathExtension("fwsc")
                if existing == nil {try data.write(to: dest, options: .atomic)}
                let scanned=Self.scanFirmwares(in:directory,nativeOnly:nativeOnly)
                DispatchQueue.main.async {
                    self.importPending=false;self.firmwares=scanned
                    if let fw=self.firmwares.first(where:{$0.url == dest}) {self.loadFirmware(fw)}
                    else {self.finishPlaybackOperation(ticket,live:self.running)}
                }
            } catch { failPlaybackOperation(error,ticket:ticket,epoch:epoch,endedImport:true) }
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "FM1", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private static func isPinnedSloop(_ bytes:Data)->Bool {
        SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined() == SloopExecutionMode.packageSHA256
    }
#if FM1_RESEARCH
    private var hasLoadedEngine:Bool {machine != nil || webEngine != nil}
#else
    private var hasLoadedEngine:Bool {machine != nil}
#endif
    private func updatePlaybackDemand() {
        playbackWanted=playbackPolicy.wantsPlayback
        playbackDemand.set(playbackPolicy.shouldRun && sampleAuditionDepth == 0)
    }
    private func beginPlaybackOperation()->Int {
        playbackTicket += 1;busy=true;return playbackTicket
    }
    private func finishPlaybackOperation(_ ticket:Int,live:Bool) {
        guard ticket == playbackTicket else{return}
        busy=false;running=live
        if !live {status=selected == nil ? "Choose a firmware to begin" : "Paused · tap Resume"}
        else {status="Running · 44.1 kHz"}
    }
    private func completePlaybackOperation(_ ticket:Int) {
        let live=playing
        DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:live)}
    }
    private func failPlaybackOperation(_ error:Error,ticket:Int,epoch:Int,endedLoad:Bool=false,endedImport:Bool=false) {
        playbackDemand.fail(epoch:epoch)
        stopWorker();saveFlash(waitForWrite:true)
        DispatchQueue.main.async {
            if endedImport {self.importPending=false}
            if endedLoad {self.firmwareLoadPending=false}
            // Scene changes preserve this epoch: real failures still hold. Only
            // an explicit newer Play/load may supersede an old failure receipt.
            guard epoch == self.playbackDemand.epoch else {
                if self.restoredSelectionNeedsLoad,self.playbackPolicy.shouldRun,!self.firmwareLoadPending,!self.importPending {self.requestPlayback()}
                return
            }
            self.playbackPolicy.hold();self.updatePlaybackDemand();self.message=error.localizedDescription
            self.finishPlaybackOperation(ticket,live:false)
        }
    }
    private func report(_ error:Error) {
        DispatchQueue.main.async {self.message=error.localizedDescription}
    }
    /// This is the only start decision. Recheck after a potentially slow engine start.
    private func applyPlaybackWorker() throws {
        if playbackDemand.shouldRun, hasLoadedEngine {
            try startWorker()
            if !playbackDemand.shouldRun {stopWorker();saveFlash(waitForWrite:true)}
        } else if playing {stopWorker();saveFlash(waitForWrite:true)}
    }
    private func queuePlayback(forceCheckpoint:Bool=false) {
        updatePlaybackDemand()
        let ticket=beginPlaybackOperation()
        let checkpointTask=forceCheckpoint ? CheckpointBackgroundTask() : nil
        worker.async { [self] in
            let epoch=playbackDemand.epoch
            do {
                if forceCheckpoint,hasLoadedEngine {stopWorker();saveFlash(waitForWrite:true)}
                try applyPlaybackWorker();completePlaybackOperation(ticket)
            } catch {failPlaybackOperation(error,ticket:ticket,epoch:epoch)}
            DispatchQueue.main.async {checkpointTask?.end()}
        }
    }
    private func requestPlayback() {
        updatePlaybackDemand()
        if restoredSelectionNeedsLoad,let selected,!firmwareLoadPending,!importPending,playbackPolicy.shouldRun {
            loadFirmware(selected)
        } else {queuePlayback()}
    }
    func sceneChanged(active:Bool,autoStart:Bool=true) {
        guard playbackPolicy.scene(active:active,autoStart:autoStart) else{return}
        if active {requestPlayback()} else {queuePlayback(forceCheckpoint:true)}
    }
    /// Suspend only app-engine execution, retaining explicit Play/Pause and
    /// interruption/route policy. The worker barrier drains its final checkpoint
    /// and shared AVAudioSession deactivation before an audition activates audio.
    @MainActor func beginSampleAudition() async -> Bool {
        let wanted=playbackWanted
        sampleAuditionDepth += 1
        queuePlayback(forceCheckpoint:true)
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            worker.async { DispatchQueue.main.async {continuation.resume()} }
        }
        return wanted
    }
    @MainActor func endSampleAudition(resume:Bool) {
        guard sampleAuditionDepth > 0 else{return}
        sampleAuditionDepth -= 1
        // Recompute the existing policy instead of calling resume(), which would
        // clear a newer manual pause or an interruption's hold authorization.
        if resume {requestPlayback()} else {queuePlayback()}
    }
    func interruptionBegan() {
        playbackPolicy.interruptionBegan();queuePlayback(forceCheckpoint:true)
    }
    func interruptionEnded(shouldResume:Bool) {
        playbackPolicy.interruptionEnded(shouldResume:shouldResume);requestPlayback()
    }
    func outputDisconnected() {
        playbackPolicy.hold();queuePlayback(forceCheckpoint:true)
    }
    /// A chooser must remain open when another operation owns the worker.
    @discardableResult func load(_ fw:Firmware)->Bool {
        guard !busy,!firmwareLoadPending,!importPending else{return false}
        playbackPolicy.play();playbackDemand.clearFailure();updatePlaybackDemand()
        loadFirmware(fw)
        return true
    }
#if FM1_RESEARCH
    /// A backend change restarts firmware while preserving the current Play/Pause
    /// intent. Native and experimental saves deliberately diverge after first use.
    func setExecutionMode(_ mode:SloopExecutionMode) {
        guard !nativeOnly,!busy,supportsExperimentalWASM,mode != executionMode,let selected else{return}
        playbackDemand.clearFailure();updatePlaybackDemand()
        loadFirmware(selected,requestedMode:mode)
    }
    func setEmulatorMHz(_ value:Int) {
        guard !busy,supportsClockControl,EmulatorClock.allowedMHz.contains(value),value != emulatorMHz,let selected else{return}
        playbackDemand.clearFailure();updatePlaybackDemand()
        loadFirmware(selected,requestedMode:.wasm,requestedMHz:value)
    }
#endif
    private static func nativeName(_ kind:UInt32)->String? {
        NativeFirmwareSupport.name(forKind:kind)
    }
    private func loadFirmware(_ fw:Firmware,requestedMode:SloopExecutionMode?=nil,requestedMHz:Int?=nil) {
        guard !firmwareLoadPending else{return}
        firmwareLoadPending=true
        let ticket=beginPlaybackOperation(),epoch=playbackDemand.epoch
#if FM1_RESEARCH
        let legacySloopMode=SloopExecutionMode(rawValue:preferences.string(forKey:SloopExecutionMode.preferenceKey) ?? "") ?? .native
#endif
        let wantedMHz=requestedMHz ?? emulatorMHz
        worker.async { [self] in
            var candidate:UnsafeMutableRawPointer?
#if FM1_RESEARCH
            var candidateWeb:WebEngineHosting?
            let previousMachine=machine,previousWeb=webEngine,previousID=activeID,previousMode=activeMode,previousFlash=webFlash
#else
            let previousMachine=machine,previousID=activeID,previousMode=activeMode
#endif
            let previousKind=activeNativeKind,previousMHz=activeGuestMHz
            var installed=false
#if FM1_RESEARCH
            var rollbackFlash=previousFlash
            var rollbackUnrecoverable=webUnrecoverable
            var rollbackPauseError=webPauseError
#endif
            do {
                let size = try fw.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard (960...4*1024*1024).contains(size) else {throw failure("Invalid firmware size.")}
                let bytes = try Data(contentsOf: fw.url)
                let nativeKind=bytes.withUnsafeBytes {instrument_native_kind_for_fwsc($0.bindMemory(to:UInt8.self).baseAddress,bytes.count)}
                let pinned=nativeKind != 0
                guard !nativeOnly || pinned else {throw failure("This instrument is not included in this version of the app.")}
                let preferenceKey="firmwareEngine.\(fw.id)"
#if FM1_RESEARCH
                let savedMode=preferences.string(forKey:preferenceKey).flatMap(SloopExecutionMode.init(rawValue:))
                let legacyMode=Self.isPinnedSloop(bytes) ? legacySloopMode : .native
                let mode:SloopExecutionMode=nativeOnly ? .native : (pinned ? (requestedMode ?? savedMode ?? legacyMode) : .wasm)
#else
                let mode:SloopExecutionMode = .native
#endif
                if mode == .native {
                    var err=[UInt8](repeating:0,count:512)
                    guard let next=bytes.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress,bytes.count,&err,err.count)}) else {throw failure(String(cString:err.map{CChar(bitPattern:$0)}))}
                    candidate=next
                    guard instrument_native_kind(next) == nativeKind else {throw failure("The selected native engine is not available in this build.")}
                }
                stopWorker()
                try checkpointActiveFlash()
#if FM1_RESEARCH
                rollbackFlash=webFlash
                rollbackUnrecoverable=webUnrecoverable;rollbackPauseError=webPauseError
#endif
                let targetURL=stateURL(fw.id,mode:mode,nativeKind:nativeKind)
                let saved:Data?=try storage.sync {
                    if FileManager.default.fileExists(atPath:targetURL.path) {return try Data(contentsOf:targetURL)}
                    if mode == .native,nativeKind == 2,
                       let legacy=try SloopVersionMigration.previousWorkspace(in:directory,preferredID:preferences.string(forKey:FirmwareSelection.preferenceKey)) {
                        // Candidate restore validates this copy before checkpointing
                        // its own versioned file. The original is never modified.
                        return legacy
                    }
#if FM1_RESEARCH
                    // First experimental start is an explicit fork of the durable
                    // native project. Existing native or WASM branches never merge.
                    if mode == .wasm {
                        // Only raw 1 MiB firmware flash may seed the CPU engine.
                        // Official Preview's logical flash is a different file.
                        let legacy=stateURL(fw.id,mode:.native,nativeKind:0)
                        if FileManager.default.fileExists(atPath:legacy.path) {return try Data(contentsOf:legacy)}
                    }
#endif
                    return nil
                }
                let expectedSize=mode == .wasm ? 1<<20 : instrument_flash(candidate,nil,0)
                guard expectedSize > 0,expectedSize <= 4*1024*1024 else {throw failure("The engine returned an invalid saved-sounds format.")}
                if let saved,saved.count != expectedSize {throw failure("The saved sounds file has an invalid size. It was kept unchanged; the firmware was not replaced.")}
#if FM1_RESEARCH
                if mode == .wasm {
                    let web=try webEngineFactory();candidateWeb=web
                    configure(web)
                    DispatchQueue.main.async {self.experimentalWebView=web.presentationView;self.displayedWebIdentity=web.identity}
                    try web.load(package:bytes,flash:saved,moduleSHA256:SloopExecutionMode.moduleSHA256,guestMHz:wantedMHz)
                    let initial=try web.request("flash")
                    guard let encoded=initial["flash"] as? String,let initialFlash=Data(base64Encoded:encoded),initialFlash.count == 1<<20 else {throw failure("Experimental WASM did not return a complete initial save. The previous engine was retained.")}
                    instrument_destroy(candidate);candidate=nil
                    webFlash=initialFlash;webPauseError=nil;webUnrecoverable=false;webDiagnostics=AudioDiagnostics()
                    machine=nil;webEngine=web
                }
#endif
                if mode == .native {
                    if let saved {
                        guard saved.withUnsafeBytes({instrument_restore(candidate,$0.bindMemory(to:UInt8.self).baseAddress,saved.count)}) else {
                            throw failure("This engine could not restore the saved sounds. The existing files and previous engine were retained.")
                        }
                    }
#if FM1_RESEARCH
                    machine=candidate;webEngine=nil;webFlash=nil;webPauseError=nil;webUnrecoverable=false
#else
                    machine=candidate
#endif
                }
                activeID=fw.id;activeMode=mode;activeNativeKind=mode == .native ? nativeKind : 0;activeGuestMHz=wantedMHz;installed=true
                try checkpointActiveFlash()
                try applyPlaybackWorker()
                // Loading must publish a real LCD even while paused or before
                // the audio device delivers its first callback. Prefill alone
                // cannot advance the normal 15 Hz display timer.
                let initialDisplay=captureNativeDisplay()
                // Commit selection only after the candidate has loaded/restored and
                // its requested playback state has started successfully.
#if FM1_RESEARCH
                instrument_destroy(previousMachine);previousWeb?.close()
                candidate=nil;candidateWeb=nil
#else
                instrument_destroy(previousMachine)
                candidate=nil
#endif
                DispatchQueue.main.async {
                    self.selected = fw; self.restoredSelectionNeedsLoad = false;self.firmwareLoadPending=false
                    self.preferences.set(fw.id, forKey: FirmwareSelection.preferenceKey)
                    self.supportsExperimentalWASM=pinned && !self.nativeOnly
                    self.nativeBackendName=Self.nativeName(nativeKind)
                    self.executionMode=mode
                    self.preferences.set(mode.rawValue,forKey:preferenceKey)
                    if Self.isPinnedSloop(bytes) {self.preferences.set(mode.rawValue,forKey:SloopExecutionMode.preferenceKey)}
                    self.emulatorMHz=wantedMHz;self.preferences.set(wantedMHz,forKey:EmulatorClock.preferenceKey)
#if FM1_RESEARCH
                    if mode != .wasm {self.experimentalWebView=nil;self.displayedWebIdentity=nil}
#endif
                    self.screen=initialDisplay?.image;self.leds=initialDisplay?.leds ?? self.leds
                    self.status = "Booting…"
                }
                publishDiagnostics(force:true)
                completePlaybackOperation(ticket)
            } catch {
                if installed {
                    stopWorker()
#if FM1_RESEARCH
                    machine=previousMachine;webEngine=previousWeb;activeID=previousID;activeMode=previousMode;activeNativeKind=previousKind;activeGuestMHz=previousMHz;webFlash=rollbackFlash;webPauseError=rollbackPauseError;webUnrecoverable=rollbackUnrecoverable
#else
                    machine=previousMachine;activeID=previousID;activeMode=previousMode;activeNativeKind=previousKind;activeGuestMHz=previousMHz
#endif
                }
#if FM1_RESEARCH
                instrument_destroy(candidate);candidateWeb?.close()
                DispatchQueue.main.async {self.experimentalWebView=previousWeb?.presentationView;self.displayedWebIdentity=previousWeb?.identity}
#else
                instrument_destroy(candidate)
#endif
                failPlaybackOperation(error,ticket:ticket,epoch:epoch,endedLoad:true)
            }
        }
    }
    func resume() {
        playbackPolicy.play();playbackDemand.clearFailure();requestPlayback()
    }
    func pause() {
        playbackPolicy.pause();queuePlayback(forceCheckpoint:true)
    }
#if FM1_RESEARCH
    func key(_ id: Int, _ down: Bool) {worker.async { [self] in if playing || !down {if let webEngine {sendWebControl(webEngine,"key",values:["key":id,"down":down])} else {instrument_key(machine,UInt32(id),down)}} }}
    func encoder(_ id: Int, _ delta: Int) {worker.async { [self] in if let webEngine {sendWebControl(webEngine,"encoder",values:["encoder":id,"delta":delta])} else {instrument_encoder(machine,UInt32(id),Int32(delta))}}}
    func master(_ value: Double) {
        volume = min(1,max(0,value))
        let level = UInt32(volume*1023)
        worker.async { [self] in workerVolume = level;if let webEngine {sendWebControl(webEngine,"master",values:["value":level])} else {instrument_volume(machine,level)} }
    }
    func toggleMute() {
        muted.toggle(); let level: Float = muted ? 0 : 0.7
        worker.async { [self] in workerMuted = level == 0;if let webEngine {sendWebControl(webEngine,"mute",values:["muted":workerMuted])} else {engine?.mainMixerNode.outputVolume = level} }
    }
#else
    func key(_ id:Int,_ down:Bool) {worker.async { [self] in if playing || !down {instrument_key(machine,UInt32(id),down)} }}
    func encoder(_ id:Int,_ delta:Int) {worker.async { [self] in instrument_encoder(machine,UInt32(id),Int32(delta)) }}
    func master(_ value:Double) {
        volume=min(1,max(0,value));let level=UInt32(volume*1023)
        worker.async { [self] in workerVolume=level;instrument_volume(machine,level) }
    }
    func toggleMute() {
        muted.toggle();let level:Float=muted ? 0 : 0.7
        worker.async { [self] in workerMuted=level == 0;engine?.mainMixerNode.outputVolume=level }
    }
#endif
#if FM1_RESEARCH
    private func sendWebControl(_ web:WebEngineHosting,_ op:String,values:[String:Any]) {
        do {_=try web.request(op,values:values)}
        catch {webFailed(error,identity:web.identity)}
    }
    private func webFailed(_ error:Error,identity:UUID) {
        guard webEngine?.identity == identity,!webUnrecoverable else{return}
        let epoch=workerPlaybackEpoch
        playbackDemand.fail(epoch:epoch);stopWorker();saveFlash(waitForWrite:true)
        webEngine?.close();webUnrecoverable=true
        DispatchQueue.main.async {
            guard epoch == self.playbackDemand.epoch else{return}
            self.playbackPolicy.hold();self.updatePlaybackDemand();self.running=false;self.message=error.localizedDescription
            self.restoredSelectionNeedsLoad=true
            self.status="Experimental engine stopped · choose Native or Resume"
        }
    }
    private func configure(_ web:WebEngineHosting) {
        let identity=web.identity
        DispatchQueue.main.async { [weak self,weak web] in
            guard let self,let web else{return}
            web.onSnapshot={ [weak self] body in
                self?.worker.async { [weak self] in
                    guard let self,self.webEngine?.identity == identity,self.playing else{return}
                    let image:CGImage?
                    if let text=body["pixels"] as? String,let data=Data(base64Encoded:text),data.count == 240*240*4,let provider=CGDataProvider(data:data as CFData) {
                        image=CGImage(width:240,height:240,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:960,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
                    } else {image=nil}
                    let leds=(body["leds"] as? [NSNumber])?.map{min(1,max(0,$0.floatValue))}
                    let state=body["state"] as? Int ?? 1
                    DispatchQueue.main.async {
                        guard self.displayedWebIdentity == identity,self.running,!self.busy,self.playbackPolicy.shouldRun else{return}
                        if let image {self.screen=image}
                        if let leds,leds.count == 41 {self.leds=leds}
                        let status=state == 2 ? "Firmware stopped" : "Running · Universal WASM"
                        if self.status != status {self.status=status}
                    }
                    if state == 2 {self.webFailed(self.failure("The experimental firmware stopped. Your previous checkpoint remains available."),identity:identity)}
                }
            }
            web.onCheckpoint={ [weak self] bytes in self?.worker.async { [weak self] in
                guard let self,self.webEngine?.identity == identity,self.playing else{return}
                self.webFlash=bytes;self.saveFlash()
            }}
            web.onDiagnostics={ [weak self] body in self?.worker.async { [weak self] in
                guard let self,self.webEngine?.identity == identity else{return}
                self.updateWebDiagnostics(body);self.publishDiagnostics(force:true)
            }}
            web.onFailure={ [weak self] error in self?.worker.async { [weak self] in self?.webFailed(error,identity:identity) }}
        }
    }
    private func updateWebDiagnostics(_ values:[String:Any]) {
        func number(_ key:String)->Double {(values[key] as? NSNumber)?.doubleValue ?? 0}
        webDiagnostics.backend = .wasm
        webDiagnostics.audioScheduling="web-worker-worklet"
        webDiagnostics.renderRatioMean=number("renderRatioMean")
        webDiagnostics.renderRatioP95=number("renderRatioP95")
        webDiagnostics.renderRatioMax=number("renderRatioMax")
        webDiagnostics.counterScope=values["counterScope"] as? String
        webDiagnostics.inputSampleRate=(values["inputSampleRate"] as? NSNumber)?.doubleValue
        webDiagnostics.audioContextSampleRate=(values["audioContextSampleRate"] as? NSNumber)?.doubleValue
        webDiagnostics.outputCounterElapsedSeconds=(values["outputCounterElapsedSeconds"] as? NSNumber)?.doubleValue
        webDiagnostics.renderRatioP95Available=values["renderRatioP95Available"] as? Bool ?? false
        webDiagnostics.wasmCompiledRegions=UInt64(max(0,number("regions")))
        webDiagnostics.wasmCompilationFailures=UInt64(max(0,number("failed")))
        webDiagnostics.wasmTailCallsSupported=values["tailCallsSupported"] as? Bool
        webDiagnostics.wasmGuestMilliseconds=number("emulatedMs")
        webDiagnostics.wasmStartupStage=values["stage"] as? String
        webDiagnostics.wasmNonzeroInputSamples=UInt64(max(0,number("nonzeroInputSamples")))
        webDiagnostics.wasmPeakAbsoluteSample=number("peakAbsoluteSample")
        webDiagnostics.missingFrames=Int(max(0,number("missingCoreFrames")))
        webDiagnostics.renderedFrames=Int(max(0,number("renderedFrames")))
        webDiagnostics.outputFrames=UInt64(max(0,number("outputRequestedFrames")))
        webDiagnostics.outputUnderrunFrames=UInt64(max(0,number("outputUnderflowFrames")))
        webDiagnostics.outputDeliveredFrames=webDiagnostics.outputFrames >= webDiagnostics.outputUnderrunFrames ? webDiagnostics.outputFrames-webDiagnostics.outputUnderrunFrames : 0
        webDiagnostics.outputUnderrunCallbacks=UInt64(max(0,number("outputUnderflowCallbacks")))
        webDiagnostics.bufferedMilliseconds=number("queuedInputFrames")/44.1
        let requested=number("requestedFrames")
        if requested>0 {webDiagnostics.renderRatioMean=number("renderTotalMs")/(requested/44.1)}
    }
#endif
    private func startWorker(allowStartupRecovery:Bool=true) throws {
        guard hasLoadedEngine, !playing else {return}
        try beforeEngineStart?()
        workerPlaybackEpoch=playbackDemand.epoch
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
#if FM1_RESEARCH
        if let webEngine {
            guard !webUnrecoverable else {throw failure("The experimental process stopped. Resume to reload its last checkpoint, or choose the native engine if available.")}
            _=try webEngine.request("master",values:["value":workerVolume])
            _=try webEngine.request("mute",values:["muted":workerMuted])
            _=try webEngine.request("play")
            playing=true;webPauseError=nil;playbackStart=ProcessInfo.processInfo.systemUptime;lastDiagnostics=playbackStart
            webEngine.startCheckpoints();return
        }
#endif
        guard let ring = AudioRing(capacity: Self.ringCapacity) else { throw failure("Could not allocate the audio buffer.") }
        let e = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        generation += 1; let g = generation
        let signal = DispatchSource.makeUserDataAddSource(queue: worker)
        signal.setEventHandler { [weak self] in self?.requestProduce(g) }
        signal.resume()
        let node = AVAudioSourceNode(format: format) { [ring, signal] isSilence, _, frames, output in
            ring.render(frames: frames, output: output)
            isSilence.pointee = false
            // User-data events coalesce; no interpreter, waiting, buffer allocation or
            // per-callback work item is performed on the real-time render thread.
            signal.add(data: 1)
            return noErr
        }
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: format)
        e.mainMixerNode.outputVolume = workerMuted ? 0 : 0.7
        engine = e; sourceNode = node; audioRing = ring; refillSignal = signal
        playing = true; producerScheduled = false
        instrument_volume(machine, workerVolume)
        health = AudioHealth(); gapSmoother = AudioGapSmoother()
        lastSnapshot = CFAbsoluteTimeGetCurrent(); lastSave = lastSnapshot
        playbackStart = ProcessInfo.processInfo.systemUptime; lastDiagnostics = playbackStart
        for _ in 0..<(Self.targetBufferedFrames / Self.framesPerBuffer) { produce(g, reschedule: false) }
        guard playing, generation == g else { return }
        playbackStart = ProcessInfo.processInfo.systemUptime
        do { try e.start() }
        catch { stopWorker(); throw error }
        afterEngineStart?(e)
        acknowledgeAudioStart(engine:e,ring:ring,generation:g,epoch:workerPlaybackEpoch,allowRecovery:allowStartupRecovery)
        requestProduce(g)
    }
    /// One bounded acknowledgement per start, with one fresh graph retry. An
    /// engine reporting `start()` success is not proof its device is consuming
    /// audio. Scene/pause/load changes invalidate this receipt before it acts.
    private func acknowledgeAudioStart(engine:AVAudioEngine,ring:AudioRing,generation g:Int,epoch:Int,allowRecovery:Bool) {
        let baseline=ring.metrics.outputFrames
        worker.asyncAfter(deadline:.now()+1) { [weak self,weak engine] in
            guard let self,let engine,self.engine === engine,self.generation == g,self.playing,
                  self.playbackDemand.shouldRun,self.playbackDemand.epoch == epoch,
                  ring.metrics.outputFrames == baseline else{return}
            self.stopWorker();self.saveFlash(waitForWrite:true)
            guard self.playbackDemand.shouldRun,self.playbackDemand.epoch == epoch else{return}
            if allowRecovery {
                do {
                    try self.startWorker(allowStartupRecovery:false)
                    if !self.playbackDemand.shouldRun || self.playbackDemand.epoch != epoch {self.stopWorker();self.saveFlash(waitForWrite:true)}
                    return
                }
                catch {self.failAudioStart(error,epoch:epoch)}
            } else {self.failAudioStart(self.failure("Audio output did not start. Your saved work was kept. Tap Resume or choose an installed firmware to try again."),epoch:epoch)}
        }
    }
    private func failAudioStart(_ error:Error,epoch:Int) {
        playbackDemand.fail(epoch:epoch);stopWorker();saveFlash(waitForWrite:true)
        DispatchQueue.main.async {
            guard epoch == self.playbackDemand.epoch else{return}
            self.playbackPolicy.hold();self.updatePlaybackDemand();self.running=false
            self.status="Paused · tap Resume";self.message=error.localizedDescription
        }
    }
    private func stopWorker() {
#if FM1_RESEARCH
        if let webEngine {
            if playing,!webUnrecoverable {
                do {webFlash=try webEngine.pause();webPauseError=nil}
                catch {
                    webPauseError=error;webUnrecoverable=true;webEngine.close();report(error)
                    DispatchQueue.main.async {
                        self.restoredSelectionNeedsLoad=true
                        self.playbackPolicy.hold();self.updatePlaybackDemand();self.running=false
                        self.status="Experimental engine stopped · last checkpoint retained"
                    }
                }
                publishDiagnostics(force:true)
            }
            playing=false
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
            return
        }
#endif
        // stop() synchronizes engine rendering before taking the final counter snapshot.
        engine?.stop()
        if playing { publishDiagnostics(force: true) }
        generation += 1; playing = false; producerScheduled = false
        refillSignal?.cancel(); refillSignal = nil
        instrument_release_all(machine)
        sourceNode = nil; engine = nil; audioRing = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func requestProduce(_ g: Int) {
        guard playing, generation == g, !producerScheduled,
              let ring = audioRing, ring.available < Self.targetBufferedFrames else { return }
        producerScheduled = true
        worker.async { [weak self] in
            guard let self, self.generation == g else { return }
            self.producerScheduled = false
            self.produce(g)
        }
    }
    /// Worker only; no audio output or playback-policy mutation is required.
    private func captureNativeDisplay()->(image:CGImage,leds:[Float])? {
        guard let machine else{return nil}
        _=instrument_snapshot(machine,&pixels,&lights)
        let data=Data(bytes:pixels,count:pixels.count*4)
        guard let provider=CGDataProvider(data:data as CFData),
              let image=CGImage(width:240,height:240,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:960,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{return nil}
        return (image,lights)
    }
    private func produce(_ g: Int, reschedule: Bool = true) {
        guard playing, generation == g, let ring = audioRing, let m = machine,
              ring.available < Self.targetBufferedFrames else { return }
        let start = ProcessInfo.processInfo.systemUptime
        let have = min(Self.framesPerBuffer, instrument_render(m, &samples, Self.framesPerBuffer))
        let renderedAt = ProcessInfo.processInfo.systemUptime
        health.record(renderSeconds: renderedAt - start, validFrames: have, frames: Self.framesPerBuffer)
        gapSmoother.process(&samples, validFrames: have, frames: Self.framesPerBuffer)
        // Target + one in-flight chunk fits the ring. Consumer can only free space,
        // so all 512 frames fit without dropping or overwriting unread audio.
        _ = ring.write(samples, frames: Self.framesPerBuffer)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSnapshot > 1.0 / 15 {
            let state = instrument_snapshot(m, &pixels, &lights)
            let data = Data(bytes: pixels, count: pixels.count * 4)
            let provider = CGDataProvider(data: data as CFData)!
            let image = CGImage(width: 240, height: 240, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 960, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            let led = lights
            let slow = health.recentRenderRatio > 1
            DispatchQueue.main.async {
                guard !self.busy,self.running,self.playbackPolicy.shouldRun else{return}
                self.screen = image; self.leds = led
                let status=state == 2 ? "Firmware stopped — try another package" : (slow ? "Audio engine is slower than real time" : "Running · 44.1 kHz")
                if self.status != status {self.status=status}
            }
            lastSnapshot = now
            if state == 2 {
                let epoch=workerPlaybackEpoch
                playbackDemand.fail(epoch:epoch);stopWorker()
                DispatchQueue.main.async {
                    guard epoch == self.playbackDemand.epoch else{return}
                    self.playbackPolicy.hold();self.updatePlaybackDemand();self.running=false
                    self.status="Firmware stopped — try another package"
                }
                return
            }
        }
        if now - lastSave > 5 { saveFlash(); lastSave = now }
        publishDiagnostics()
        // Keep producing continuously while late; never wait for a completed audio
        // buffer before starting the next emulation chunk. Yield between chunks so
        // queued keys/knobs/pause remain responsive on this same serial worker.
        if reschedule { requestProduce(g) }
    }
    /// Capture counters at a worker-queue boundary without resetting metrics or writing to disk.
    func captureAudioDiagnostics(completion: @escaping (AudioDiagnostics) -> Void) {
        worker.async { [self] in
            let report = makeDiagnostics(now: ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.async { completion(report) }
        }
    }
    private func makeDiagnostics(now: TimeInterval) -> AudioDiagnostics {
#if FM1_RESEARCH
        var diagnostic = webEngine == nil ? health.diagnostics(elapsed: now - playbackStart) : webDiagnostics
#else
        var diagnostic = health.diagnostics(elapsed:now-playbackStart)
#endif
        let sessionElapsed=max(0,now-playbackStart)
        diagnostic.playbackSessionElapsedSeconds=sessionElapsed
        // WASM output counters survive pause/resume; use their matching cumulative
        // AudioContext-frame duration, while preserving current-play elapsed separately.
#if FM1_RESEARCH
        diagnostic.elapsedSeconds=webEngine == nil ? sessionElapsed : (diagnostic.outputCounterElapsedSeconds ?? sessionElapsed)
#else
        diagnostic.elapsedSeconds=sessionElapsed
#endif
        diagnostic.firmware = activeID
#if FM1_RESEARCH
        diagnostic.backend = webEngine == nil ? AudioBackend(coreCode: instrument_backend(machine)) : .wasm
#else
        diagnostic.backend=AudioBackend(coreCode:instrument_backend(machine))
#endif
        diagnostic.executionMode=activeMode.rawValue
        diagnostic.nativeEngine=Self.nativeName(activeNativeKind)
#if FM1_RESEARCH
        if webEngine != nil {diagnostic.wasmModuleSHA256=SloopExecutionMode.moduleSHA256;diagnostic.guestClockHz=UInt64(activeGuestMHz)*1000000}
#endif
        // This decoder describes SLOOP's counter layout. Other native source
        // engines have different voice/part counters; do not mislabel them.
        if diagnostic.backend == .native,activeNativeKind == 2 {
            var counters=[UInt64](repeating:0,count:16)
            if instrument_workload_metrics(machine,&counters,16) == 16 {
                diagnostic.nativeWorkload = NativeWorkloadDiagnostics(counters:counters)
            }
        }
        if let metrics = audioRing?.metrics {
            diagnostic.outputFrames = metrics.outputFrames
            diagnostic.outputDeliveredFrames = metrics.deliveredFrames
            diagnostic.outputUnderrunFrames = metrics.underrunFrames
            diagnostic.outputUnderrunCallbacks = metrics.underrunCallbacks
            diagnostic.bufferedMilliseconds = Double(metrics.bufferedFrames) / 44.1
        }
        var system = utsname(); uname(&system)
        let machineCapacity = MemoryLayout.size(ofValue: system.machine)
        diagnostic.device = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: machineCapacity) { String(cString: $0) }
        }
        diagnostic.system = ProcessInfo.processInfo.operatingSystemVersionString
        diagnostic.lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        diagnostic.thermalState = ProcessInfo.processInfo.thermalState.rawValue
        diagnostic.hardwareSampleRate = AVAudioSession.sharedInstance().sampleRate
        diagnostic.hardwareIOSeconds = AVAudioSession.sharedInstance().ioBufferDuration
        diagnostic.updatedAt = Date()
        return diagnostic
    }
    private func publishDiagnostics(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastDiagnostics >= 2 else { return }
        lastDiagnostics = now
        let report = makeDiagnostics(now: now)
        DispatchQueue.main.async { self.audioDiagnostics = report }
        let url = directory.deletingLastPathComponent().appendingPathComponent("AudioDiagnostics.json")
        storage.async {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(report) { try? data.write(to: url, options: .atomic) }
        }
    }
    private func stateURL(_ id:String,mode:SloopExecutionMode?=nil,nativeKind:UInt32?=nil)->URL {
        let engineMode=mode ?? activeMode,kind=nativeKind ?? activeNativeKind
        let suffix=engineMode == .wasm ? "wasm.flash" : (kind == 6 ? "preview.flash" : "flash")
        return directory.appendingPathComponent(id).appendingPathExtension(suffix)
    }
    private func activeFlash()throws->Data? {
#if FM1_RESEARCH
        if let webPauseError {throw webPauseError}
        if webEngine != nil {return webFlash}
#endif
        guard let machine else{return nil}
        let size=instrument_flash(machine,nil,0)
        guard size > 0,size <= 4*1024*1024 else {throw failure("The engine did not provide a complete saved-sounds snapshot.")}
        var data=Data(count:size)
        data.withUnsafeMutableBytes {_=instrument_flash(machine,$0.bindMemory(to:UInt8.self).baseAddress,size)}
        return data
    }
    /// Used for a transaction boundary: failure aborts replacement rather than
    /// merely posting an asynchronous disk warning and discarding the old engine.
    private func checkpointActiveFlash()throws {
        // A dead content process has no trustworthy newer snapshot. Keep its
        // durable last checkpoint byte-for-byte and allow an explicit recovery
        // load (Native or WASM) from that checkpoint.
#if FM1_RESEARCH
        if webUnrecoverable {return}
#endif
        guard let id=activeID,let snapshot=try activeFlash() else{return}
        let url=stateURL(id),key=url.lastPathComponent
        try storage.sync {
            let digest=Data(SHA256.hash(data:snapshot))
            guard digest != flashDigests[key] else{return}
            try snapshot.write(to:url,options:.atomic);flashDigests[key]=digest
        }
    }
    private func saveFlash(waitForWrite: Bool = false) {
        guard !nativeReplacementUncommitted else{return}
        guard let id=activeID else{return}
        let snapshot:Data
        do {guard let bytes=try activeFlash() else{return};snapshot=bytes}
        catch {report(error);return}
        let url = stateURL(id),key=url.lastPathComponent
        let persist = { [self] in
            let digest = Data(SHA256.hash(data: snapshot))
            guard digest != flashDigests[key] else { return }
            do { try snapshot.write(to: url, options: .atomic); flashDigests[key] = digest }
            catch { report(error) }
        }
        // Pause has already stopped audio and waits for durable persistence. Automatic
        // checkpoints only copy emulated flash here; hashing and I/O run on storage.
        if waitForWrite { storage.sync(execute: persist) }
        else { storage.async(execute: persist) }
    }
}

/// Keeps a foreground-loss checkpoint alive for the system's allowed grace period.
private final class CheckpointBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save instrument") { [weak self] in self?.end() }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid
    }
}

enum AudioBackend: String, Codable {
    case interpreter, native,wasm
    init?(coreCode: UInt32) {
        switch coreCode {
        case 1: self = .interpreter
        case 2: self = .native
        default: return nil
        }
    }
    var displayName:String {switch self {case .native:return "Compiled native";case .interpreter:return "Firmware interpreter";case .wasm:return "Universal WASM"}}
}

/// Read on the emulator worker. Peaks/counters describe this instance since boot.
/// Effect bits report observed configuration, not separate effect audibility.
struct NativeWorkloadDiagnostics: Codable, Equatable {
    let renderedFrames, peakSharedSynthVoices, peakDrumVoices, voiceKills: UInt64
    let nonzeroDSPSamples, peakRawQ15Magnitude, configuredEffectMask, activeTrackMask: UInt64
    let framesWhilePlaying: UInt64
    let peakTrackSynthVoices: [UInt64]
    let peakLiveGrains: UInt64
    // Optional so aggregate reports produced before the input queue remain readable.
    let droppedKeyTransitions, keyTransitionQueueHighWater, pendingKeyTransitions: UInt64?
    init?(counters:[UInt64]) {
        guard counters.count == 16 else {return nil}
        renderedFrames=counters[0];peakSharedSynthVoices=counters[1];peakDrumVoices=counters[2];voiceKills=counters[3]
        nonzeroDSPSamples=counters[4];peakRawQ15Magnitude=counters[5];configuredEffectMask=counters[6];activeTrackMask=counters[7]
        framesWhilePlaying=counters[8];peakTrackSynthVoices=Array(counters[9...11]);peakLiveGrains=counters[12]
        droppedKeyTransitions=counters[13];keyTransitionQueueHighWater=counters[14];pendingKeyTransitions=counters[15]
    }
}

/// Local aggregate measurements only; no firmware bytes, user input or audio is recorded.
struct AudioDiagnostics: Codable, Equatable {
    var nativeEngine:String?
    var firmware: String?
    var backend: AudioBackend?
    var executionMode:String?
    var wasmModuleSHA256:String?
    var guestClockHz:UInt64?
    var wasmCompiledRegions:UInt64?
    var wasmCompilationFailures:UInt64?
    var wasmTailCallsSupported:Bool?
    var wasmGuestMilliseconds:Double?
    var wasmStartupStage:String?
    var wasmNonzeroInputSamples:UInt64?
    var wasmPeakAbsoluteSample:Double?
    var renderRatioP95Available:Bool?
    var nativeWorkload: NativeWorkloadDiagnostics?
    var device = ""
    var system = ""
    var lowPowerModeEnabled: Bool?
    /// ProcessInfo.ThermalState raw value: nominal 0, fair 1, serious 2, critical 3.
    var thermalState: Int?
    var updatedAt = Date()
    var elapsedSeconds: Double = 0
    var playbackSessionElapsedSeconds: Double?
    var outputCounterElapsedSeconds: Double?
    var counterScope: String?
    var inputSampleRate: Double?
    var audioContextSampleRate: Double?
    var sampleRate: Double = 44100
    var hardwareSampleRate: Double = 0
    var hardwareIOSeconds: Double = 0
    var audioScheduling = "source-ring"
    var lookaheadMilliseconds: Double = 1536 / 44.1
    var maximumBufferedMilliseconds: Double = 2048 / 44.1
    var bufferedMilliseconds: Double = 0
    var outputFrames: UInt64 = 0
    var outputDeliveredFrames: UInt64 = 0
    var outputUnderrunFrames: UInt64 = 0
    var outputUnderrunCallbacks: UInt64 = 0
    var renderedFrames = 0
    var missingFrames = 0
    var renderRatioMean: Double = 0
    /// Native: recent256 buffers; WASM: recent128 chunks. Above1 exceeds real time.
    var renderRatioP95: Double = 0
    var renderRatioMax: Double = 0
    var estimatedQueueGaps = 0
    var estimatedGapSeconds: Double = 0
    var largestEstimatedGapSeconds: Double = 0
}

struct AudioHealth {
    private var ratios: [Double] = []
    private var ratioIndex = 0
    private var renderSeconds: Double = 0
    private var requestedFrames = 0
    private var maximumRatio: Double = 0
    private var validFrames = 0
    private var missingFrames = 0
    private var gapCount = 0
    private var gapSeconds: Double = 0
    private var largestGap: Double = 0

    var recentRenderRatio: Double { ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count) }
    mutating func record(renderSeconds: Double, validFrames: Int, frames: Int) {
        guard frames > 0 else { return }
        let duration = max(0, renderSeconds)
        let ratio = duration * 44100 / Double(frames)
        if ratios.count < 256 { ratios.append(ratio) }
        else { ratios[ratioIndex] = ratio; ratioIndex = (ratioIndex + 1) % 256 }
        self.renderSeconds += duration
        requestedFrames += frames
        self.validFrames += min(frames, max(0, validFrames))
        missingFrames += frames - min(frames, max(0, validFrames))
        maximumRatio = max(maximumRatio, ratio)
    }
    mutating func recordGap(seconds: Double) {
        guard seconds > 0 else { return }
        gapCount += 1; gapSeconds += seconds; largestGap = max(largestGap, seconds)
    }
    func diagnostics(elapsed: Double) -> AudioDiagnostics {
        var result = AudioDiagnostics()
        result.elapsedSeconds = max(0, elapsed)
        result.renderedFrames = validFrames; result.missingFrames = missingFrames
        result.renderRatioMean = requestedFrames == 0 ? 0 : renderSeconds * 44100 / Double(requestedFrames)
        let sorted = ratios.sorted()
        result.renderRatioP95 = sorted.isEmpty ? 0 : sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        result.renderRatioMax = maximumRatio
        result.estimatedQueueGaps = gapCount; result.estimatedGapSeconds = gapSeconds
        result.largestEstimatedGapSeconds = largestGap
        return result
    }
}

/// De-click only unavailable audio and its recovery; complete firmware buffers pass unchanged.
struct AudioGapSmoother {
    private var recovering = false
    private var lastLeft: Float = 0
    private var lastRight: Float = 0
    mutating func process(_ samples: inout [Float], validFrames: Int, frames: Int) {
        guard frames > 0, samples.count >= frames * 2 else { return }
        let valid = min(frames, max(0, validFrames))
        if recovering && valid > 0 {
            let fade = min(64, valid)
            for index in 0..<fade {
                let gain = Float(index + 1) / Float(fade)
                samples[index * 2] *= gain; samples[index * 2 + 1] *= gain
            }
        }
        if valid < frames {
            let left = valid > 0 ? samples[(valid - 1) * 2] : lastLeft
            let right = valid > 0 ? samples[(valid - 1) * 2 + 1] : lastRight
            let fade = min(64, frames - valid)
            for index in valid..<frames {
                let gain = max(0, 1 - Float(index - valid + 1) / Float(fade))
                samples[index * 2] = left * gain; samples[index * 2 + 1] = right * gain
            }
        }
        recovering = valid < frames
        lastLeft = samples[(frames - 1) * 2]; lastRight = samples[(frames - 1) * 2 + 1]
    }
}

extension Instrument {
    /// Reset only this release's native saved-data image. App project copies,
    /// other releases and host playback/volume/mute preferences are untouched.
    @MainActor func resetCurrentFirmware()async throws->FirmwareResetRecovery {
        try await replaceCurrentNativeSavedData(restoring:nil)
    }
    /// A session token authorizes restoring only its exact selected package.
    @MainActor func restoreFirmwareReset(_ recovery:FirmwareResetRecovery)async throws {
        _=try await replaceCurrentNativeSavedData(restoring:recovery)
    }
    private static func resetDigest(_ bytes:Data)->String {
        SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    }
    private func checkedResetRoot()throws->URL {
        let root=directory.resolvingSymlinksInPath().appendingPathComponent("ResetRecovery",isDirectory:true)
        let manager=FileManager.default
        guard (try? manager.destinationOfSymbolicLink(atPath:root.path)) == nil else {throw failure("The recovery location is a link. Saved data was kept unchanged.")}
        var isDirectory:ObjCBool=false
        if manager.fileExists(atPath:root.path,isDirectory:&isDirectory) {
            guard isDirectory.boolValue else {throw failure("The recovery location is not a folder.")}
        } else {try manager.createDirectory(at:root,withIntermediateDirectories:false)}
        guard try URL(fileURLWithPath:root.path).resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true else {throw failure("The recovery location is not a folder.")}
        return root
    }
    private func checkedResetFile(_ file:URL)throws->Data {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath:file.path)) == nil,
              try URL(fileURLWithPath:file.path).resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true else {throw failure("The recovery copy is not a regular file. Saved data was kept unchanged.")}
        return try Data(contentsOf:file)
    }
    private func writeResetFile(_ bytes:Data,to file:URL)throws {
        try bytes.write(to:file,options:.atomic)
        let handle=try FileHandle(forWritingTo:file)
        defer {try? handle.close()}
        try handle.synchronize()
        guard try Data(contentsOf:file) == bytes else {throw failure("The recovery copy could not be verified. Saved data was kept unchanged.")}
    }
    private func resetFlash(_ pointer:UnsafeMutableRawPointer)throws->Data {
        let size=instrument_flash(pointer,nil,0)
        guard size>0,size<=4*1024*1024 else {throw failure("The native engine did not provide a complete saved-data image.")}
        var bytes=Data(count:size)
        let copied=bytes.withUnsafeMutableBytes {instrument_flash(pointer,$0.bindMemory(to:UInt8.self).baseAddress,size)}
        guard copied == size else {throw failure("The native saved-data image was incomplete.")}
        return bytes
    }
    @MainActor private func replaceCurrentNativeSavedData(restoring recovery:FirmwareResetRecovery?)async throws->FirmwareResetRecovery {
        try Task.checkCancellation()
        guard !busy,!firmwareLoadPending,!importPending,let selected else {throw failure("Wait for the selected instrument to finish loading.")}
        guard executionMode == .native,nativeBackendName != nil,sampleAuditionDepth == 0 else {throw failure("Choose a loaded native instrument and finish any sample preview before replacing saved data.")}
        firmwareLoadPending=true
        let ticket=beginPlaybackOperation(),epoch=playbackDemand.epoch
        return try await withCheckedThrowingContinuation {continuation in
            // Enqueue on worker immediately: lifecycle operations cannot finish a
            // newer ticket ahead of a reset still waiting on the storage queue.
            worker.async { [self] in
                var candidate:UnsafeMutableRawPointer?
                let previous=machine
                var stopped=false,installed=false
                do {
                    guard activeID == selected.id,activeMode == .native,activeNativeKind != 0,let previous,
                          instrument_native_kind(previous) == activeNativeKind else {throw failure("The selected native instrument changed. Saved data was kept unchanged.")}
                    let package=try storage.sync {try Data(contentsOf:selected.url)}
                    let digest=Self.resetDigest(package)
                    guard Self.nativeKind(package) == activeNativeKind,
                          let entry=CatalogFirmware.available.first(where:{$0.sha256 == digest}) else {throw failure("The selected package no longer matches its compiled release. Saved data was kept unchanged.")}
                    let kind=activeNativeKind,autosave=stateURL(selected.id)
                    let restored:Data?=try storage.sync {
                        // Reject links/directories instead of following a path
                        // outside the selected release's owned autosave entry.
                        if (try? FileManager.default.destinationOfSymbolicLink(atPath:autosave.path)) != nil {throw failure("The selected autosave is a link. Saved data was kept unchanged.")}
                        if FileManager.default.fileExists(atPath:autosave.path) {_=try checkedResetFile(autosave)}
                        guard let recovery else{return nil}
                        let root=try checkedResetRoot(),folder=recovery.backupURL.deletingLastPathComponent()
                        guard recovery.firmwareID == selected.id,recovery.packageSHA256 == digest,
                              folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
                              folder.lastPathComponent == recovery.id.uuidString,recovery.backupURL.lastPathComponent == "original.flash",
                              (try? FileManager.default.destinationOfSymbolicLink(atPath:folder.path)) == nil else {throw failure("This recovery copy belongs to another instrument or location.")}
                        let receiptBytes=try checkedResetFile(folder.appendingPathComponent("receipt.json"))
                        guard Self.resetDigest(receiptBytes) == recovery.receiptSHA256 else {throw failure("The recovery receipt changed. Current saved data was kept.")}
                        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
                        let receipt=try decoder.decode(FirmwareResetReceipt.self,from:receiptBytes)
                        let bytes=try checkedResetFile(recovery.backupURL)
                        guard receipt.schemaVersion == 1,receipt.id == recovery.id,receipt.firmwareID == selected.id,
                              receipt.packageSHA256 == digest,receipt.packageVersion == entry.version,receipt.nativeKind == kind,
                              receipt.autosaveFilename == autosave.lastPathComponent,receipt.originalBytes == bytes.count,
                              receipt.originalSHA256 == Self.resetDigest(bytes) else {throw failure("The recovery saved data could not be verified. Current saved data was kept.")}
                        return bytes
                    }
                    var error=[UInt8](repeating:0,count:512)
                    guard let next=package.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress,package.count,&error,error.count)}) else {throw failure("The native instrument could not be created. Saved data was kept unchanged.")}
                    candidate=next
                    guard instrument_native_kind(next) == kind else {throw failure("The required native engine is unavailable.")}
                    if let restored {
                        guard restored.count == instrument_flash(next,nil,0),restored.withUnsafeBytes({instrument_restore(next,$0.bindMemory(to:UInt8.self).baseAddress,restored.count)}) else {throw failure("The engine could not restore the complete recovery image.")}
                    }
                    // Initialize defaults/display through the real source engine
                    // even if host playback is paused. No audio device is started.
                    instrument_volume(next,workerVolume)
                    var warmup=[Float](repeating:0,count:1024)
                    guard instrument_render(next,&warmup,512) == 512,warmup.allSatisfy(\.isFinite) else {throw failure("The replacement native engine did not initialize correctly.")}
                    let replacement=try resetFlash(next)
                    guard let original=try activeFlash(),original.count == replacement.count else {throw failure("The current native saved data could not be backed up completely.")}
                    let tokenAndStage:(FirmwareResetRecovery,URL)=try storage.sync {
                        let root=try checkedResetRoot(),id=UUID(),folder=root.appendingPathComponent(id.uuidString,isDirectory:true)
                        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
                        let originalURL=folder.appendingPathComponent("original.flash")
                        let receipt=FirmwareResetReceipt(schemaVersion:1,id:id,firmwareID:selected.id,firmwareName:selected.name,packageSHA256:digest,packageVersion:entry.version,nativeKind:kind,originalSHA256:Self.resetDigest(original),originalBytes:original.count,autosaveFilename:autosave.lastPathComponent,createdAt:Date())
                        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
                        let receiptBytes=try encoder.encode(receipt)
                        try writeResetFile(original,to:originalURL)
                        try writeResetFile(receiptBytes,to:folder.appendingPathComponent("receipt.json"))
                        let stage=folder.appendingPathComponent("replacement.flash")
                        try writeResetFile(replacement,to:stage)
                        return (FirmwareResetRecovery(id:id,firmwareID:selected.id,packageSHA256:digest,backupURL:originalURL,receiptSHA256:Self.resetDigest(receiptBytes)),stage)
                    }
                    stopWorker();stopped=true
                    nativeReplacementUncommitted=true
                    machine=next;installed=true
                    try applyPlaybackWorker()
                    let display=captureNativeDisplay()
                    // All validation, backup, staging and audio start can fail
                    // before this sole commit. rename failure retains the old
                    // entry; after successful rename no throwing work remains.
                    try storage.sync {
                        let result=tokenAndStage.1.path.withCString {source in autosave.path.withCString {destination in Darwin.rename(source,destination)}}
                        guard result == 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"The instrument's saved data could not be replaced. Previous data was kept."])}
                        flashDigests[autosave.lastPathComponent]=Data(SHA256.hash(data:replacement))
                    }
                    nativeReplacementUncommitted=false
                    instrument_destroy(previous);candidate=nil
                    publishDiagnostics(force:true)
                    let live=playing
                    DispatchQueue.main.async {
                        self.firmwareLoadPending=false;self.screen=display?.image;self.leds=display?.leds ?? self.leds
                        self.finishPlaybackOperation(ticket,live:live)
                        continuation.resume(returning:tokenAndStage.0)
                    }
                } catch {
                    var resultError=error
                    var restartFailed=false
                    if installed {stopWorker();machine=previous}
                    nativeReplacementUncommitted=false
                    instrument_destroy(candidate)
                    if stopped {
                        do {try applyPlaybackWorker()}
                        catch {
                            restartFailed=true;playbackDemand.fail(epoch:epoch)
                            resultError=failure("Previous saved data and instrument were kept, but audio could not restart. Tap Resume to retry. \(resultError.localizedDescription)")
                        }
                    }
                    let live=playing,returnedError=resultError,holdForRetry=restartFailed
                    DispatchQueue.main.async {
                        if holdForRetry,epoch == self.playbackDemand.epoch {self.playbackPolicy.hold();self.updatePlaybackDemand()}
                        self.firmwareLoadPending=false;self.finishPlaybackOperation(ticket,live:live)
                        continuation.resume(throwing:returnedError)
                    }
                }
            }
        }
    }
    /// The file service never accesses an engine from its disk or UI queue.
    @MainActor func captureSloopExportContext() async throws -> (snapshot:SloopWorkSnapshot,package:Data) {
        guard !busy,let selected else {throw ProjectFilesError("Wait for the instrument to finish loading.")}
        let ticket=beginPlaybackOperation()
        return try await withCheckedThrowingContinuation {continuation in
            storage.async { [self] in
                do {
                    let package=try Data(contentsOf:selected.url)
                    worker.async { [self] in
                        do {
                            guard activeID == selected.id,activeMode == .native,activeNativeKind == 2,let machine else {throw ProjectFilesError("Select native SLOOP 2.8 to use project files.")}
                            let snapshot=try SloopWorkSnapshot.capture(machine:machine,master:workerVolume)
                            let live=playing
                            DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:live);continuation.resume(returning:(snapshot,package))}
                        } catch {
                            let live=playing
                            DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:live);continuation.resume(throwing:error)}
                        }
                    }
                } catch {DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:self.running);continuation.resume(throwing:error)}}
            }
        }
    }
    /// Candidate validation leaves the live engine untouched. The last current
    /// work is captured again at the swap boundary, then written before replacement.
    @MainActor func replaceSloopWork(_ snapshot:SloopWorkSnapshot,kind:ProjectFileKind,recoveryURL:URL,sampleSlot:Int?=nil,sampleTrack:Int?=nil)async throws {
        guard !busy,let selected else {throw ProjectFilesError("Wait for the instrument to finish loading.")}
        let ticket=beginPlaybackOperation()
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            storage.async { [self] in
                do {
                    let package=try Data(contentsOf:selected.url)
                    worker.async { [self] in
                        var candidate:UnsafeMutableRawPointer?
                        var stopped=false,installed=false
                        let previous=machine,previousVolume=workerVolume
                        var rollbackFlash:Data?
                        do {
                            guard activeID == selected.id,activeMode == .native,activeNativeKind == 2,let previous else {throw ProjectFilesError("Select native SLOOP 2.8 before opening this workspace.")}
                            let recovery=try SloopWorkSnapshot.capture(machine:previous,master:workerVolume)
                            let applied:SloopWorkSnapshot
                            if let sampleSlot {applied=try recovery.replacingSample(snapshot.bytes("sample\(sampleSlot)"),slot:sampleSlot)}
                            else {applied=kind == .project ? try snapshot.projectOverlay(on:recovery) : snapshot}
                            if let sampleTrack {
                                guard (0..<3).contains(sampleTrack),let sampleSlot,(0..<4).contains(sampleSlot) else {throw ProjectFilesError("Choose Track 1–3 and a valid user sample slot.")}
                            }
                            candidate=try applied.nativeCreate(package:package)
                            if let sampleTrack,let sampleSlot {
                                let result=instrument_sloop_sample_assign(candidate,UInt32(sampleTrack),UInt32(sampleSlot))
                                guard result == 0 else {throw ProjectFilesError("The sample could not be assigned to Track \(sampleTrack+1) (\(result)). Your current work was kept.")}
                                guard instrument_sloop_commit(candidate) == 0 else {throw ProjectFilesError("The assigned sample could not be saved. Your current work was kept.")}
                            }
                            rollbackFlash=try activeFlash()
                            stopWorker();stopped=true
                            let envelope=ProjectFileEnvelope(name:"Recovery before replacement",kind:.backup,snapshot:recovery)
                            try storage.sync {
                                try FileManager.default.createDirectory(at:recoveryURL.deletingLastPathComponent(),withIntermediateDirectories:true)
                                try envelope.encoded().write(to:recoveryURL,options:.atomic)
                                _ = try ProjectFileEnvelope.read(recoveryURL)
                            }
                            machine=candidate;workerVolume=applied.master;installed=true
                            try checkpointActiveFlash()
                            try applyPlaybackWorker()
                            instrument_destroy(previous);candidate=nil
                            let initialDisplay=captureNativeDisplay()
                            publishDiagnostics(force:true)
                            let live=playing
                            DispatchQueue.main.async {self.screen=initialDisplay?.image;self.leds=initialDisplay?.leds ?? self.leds;self.volume=Double(applied.master)/1023;self.finishPlaybackOperation(ticket,live:live);continuation.resume()}
                        } catch {
                            if installed {
                                stopWorker();machine=previous;workerVolume=previousVolume
                                if let rollbackFlash {
                                    let url=stateURL(selected.id),key=url.lastPathComponent
                                    do {try storage.sync {try rollbackFlash.write(to:url,options:.atomic);flashDigests[key]=Data(SHA256.hash(data:rollbackFlash))}}
                                    catch {report(ProjectFilesError("The previous engine was retained. Its complete recovery backup is safe, but its automatic save could not be rewritten: \(error.localizedDescription)"))}
                                }
                            }
                            instrument_destroy(candidate)
                            if stopped {do {try applyPlaybackWorker()}catch {report(error)}}
                            let live=playing
                            DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:live);continuation.resume(throwing:error)}
                        }
                    }
                } catch {DispatchQueue.main.async {self.finishPlaybackOperation(ticket,live:self.running);continuation.resume(throwing:error)}}
            }
        }
    }
}
