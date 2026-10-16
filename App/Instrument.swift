import SwiftUI
import AVFoundation
import CryptoKit

struct Firmware: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

/// All emulator state and AVAudioPlayerNode scheduling belong to the worker queue.
/// The audio callback only schedules a worker job; it never interprets CPU instructions.
final class Instrument: ObservableObject {
    @Published var firmwares: [Firmware] = []
    @Published var selected: Firmware?
    @Published var running = false
    @Published var busy = false
    @Published var message: String?
    @Published var screen: CGImage?
    @Published var leds: [Float] = Array(repeating: 0, count: 41)
    @Published var status = "Choose a firmware to begin"
    @Published var muted = false
    @Published var volume: Double = 0.7
    private let worker = DispatchQueue(label: "fm1.instrument", qos: .userInteractive)
    private var machine: UnsafeMutableRawPointer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var generation = 0
    private var playing = false
    private var activeID: String?
    private var lastSnapshot = CFAbsoluteTimeGetCurrent()
    private var lastSave = CFAbsoluteTimeGetCurrent()
    private var renderedFrames = 0
    private var missingFrames = 0
    private var flashDigest: Data?
    private var workerMuted = false
    private var workerVolume: UInt32 = 716
    private var pixels = [UInt32](repeating: 0, count: 240*240)
    private var lights = [Float](repeating: 0, count: 41)
    private var samples = [Float](repeating: 0, count: 1024)
    private var observations: [NSObjectProtocol] = []
    let directory: URL
    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Firmwares", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { message = error.localizedDescription }
        refresh()
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               AVAudioSession.InterruptionType(rawValue: raw) == .began { self?.pause() }
        })
        observations.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { self?.pause() }
        })
    }
    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        firmwares = files.filter {$0.pathExtension.lowercased() == "fwsc"}.map {
            Firmware(id: $0.deletingPathExtension().lastPathComponent, name: $0.deletingPathExtension().lastPathComponent, url: $0)
        }.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    func importFirmware(_ url: URL) {
        busy = true
        worker.async { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size >= 960 && size <= 4*1024*1024 else { throw failure("Choose an FM-1 .fwsc package smaller than 4 MB.") }
                let data = try Data(contentsOf: url)
                var err = [UInt8](repeating: 0, count: 512)
                guard let candidate = data.withUnsafeBytes({ instrument_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &err, err.count) }) else {
                    throw failure(String(cString: err.map { CChar(bitPattern: $0) }))
                }
                instrument_destroy(candidate)
                // Identical imports reuse a file; a different version never overwrites its predecessor.
                let digest = SHA256.hash(data: data).prefix(4).map {String(format:"%02x",$0)}.joined()
                let name = String(url.deletingPathExtension().lastPathComponent.prefix(64)) + " · " + digest
                let dest = directory.appendingPathComponent(name).appendingPathExtension("fwsc")
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async { self.refresh(); self.busy = false; if let fw = self.firmwares.first(where: {$0.url == dest}) { self.load(fw) } }
            } catch { report(error) }
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "FM1", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func report(_ error: Error) {
        DispatchQueue.main.async { self.busy = false; self.message = error.localizedDescription }
    }
    func load(_ fw: Firmware) {
        guard !busy else {return}
        busy = true
        worker.async { [self] in
            do {
                let size = try fw.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard (960...4*1024*1024).contains(size) else {throw failure("Invalid firmware size.")}
                let bytes = try Data(contentsOf: fw.url)
                var err = [UInt8](repeating: 0, count: 512)
                guard let next = bytes.withUnsafeBytes({instrument_create($0.bindMemory(to:UInt8.self).baseAddress, bytes.count, &err, err.count)}) else {
                    throw failure(String(cString:err.map{CChar(bitPattern:$0)}))
                }
                stopWorker()
                saveFlash()
                instrument_destroy(machine)
                machine = next; activeID = fw.id; flashDigest = nil
                if let saved = try? Data(contentsOf: stateURL(fw.id)) {
                    _ = saved.withUnsafeBytes {instrument_restore(next,$0.bindMemory(to:UInt8.self).baseAddress,saved.count)}
                }
                DispatchQueue.main.async { self.selected = fw; self.screen = nil; self.status = "Booting…" }
                try startWorker()
                let live = playing
                DispatchQueue.main.async { self.busy = false; self.running = live }
            } catch { report(error) }
        }
    }
    func resume() {
        guard !busy else {return}
        if selected == nil {return}
        busy = true
        worker.async { [self] in
            do {try startWorker(); let live=playing; DispatchQueue.main.async {self.busy=false;self.running=live}}
            catch {report(error)}
        }
    }
    func pause() {
        worker.async { [self] in
            stopWorker(); saveFlash()
            DispatchQueue.main.async {self.running = false; self.status = self.selected == nil ? "Choose a firmware to begin" : "Paused"}
        }
    }
    func key(_ id: Int, _ down: Bool) {worker.async { [self] in if playing || !down {instrument_key(machine,UInt32(id),down)} }}
    func encoder(_ id: Int, _ delta: Int) {worker.async { [self] in instrument_encoder(machine,UInt32(id),Int32(delta))}}
    func master(_ value: Double) {
        volume = min(1,max(0,value))
        let level = UInt32(volume*1023)
        worker.async { [self] in workerVolume = level; instrument_volume(machine,level) }
    }
    func toggleMute() {
        muted.toggle(); let level: Float = muted ? 0 : 0.7
        worker.async { [self] in workerMuted = level == 0; player?.volume = level }
    }
    private func startWorker() throws {
        guard machine != nil, !playing else {return}
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        let e = AVAudioEngine(); let p = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        e.attach(p);e.connect(p,to:e.mainMixerNode,format:format)
        try e.start()
        engine = e;player = p;p.volume = workerMuted ? 0 : 0.7
        instrument_volume(machine,workerVolume)
        playing = true;generation += 1; renderedFrames=0;missingFrames=0
        let g = generation
        for _ in 0..<3 {produce(g)}
        p.play()
    }
    private func stopWorker() {
        generation += 1;playing = false
        for id in 0..<41 {instrument_key(machine,UInt32(id),false)}
        player?.stop();engine?.stop();player=nil;engine=nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func produce(_ g: Int) {
        guard playing, generation == g, let p=player, let m=machine else {return}
        let start=CFAbsoluteTimeGetCurrent()
        let have=instrument_render(m,&samples,512)
        renderedFrames += have;missingFrames += 512-have
        let format=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
        buffer.frameLength=512
        for i in 0..<512 {buffer.floatChannelData![0][i]=samples[2*i];buffer.floatChannelData![1][i]=samples[2*i+1]}
        p.scheduleBuffer(buffer, completionCallbackType:.dataConsumed) { [weak self] _ in
            guard let self else {return}; self.worker.async {self.produce(g)}
        }
        if start-lastSnapshot > 1.0/15 {
            let state=instrument_snapshot(m,&pixels,&lights)
            let data=Data(bytes:pixels,count:pixels.count*4)
            let provider=CGDataProvider(data:data as CFData)!
            let image=CGImage(width:240,height:240,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:960,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
            let led=lights
            let slow=CFAbsoluteTimeGetCurrent()-start > 0.024
            DispatchQueue.main.async {self.screen=image;self.leds=led;self.status=state == 2 ? "Firmware stopped — try another package" : (slow ? "Emulation is slower than real time" : "Running · 44.1 kHz")}
            lastSnapshot=start
            if state==2 {stopWorker();DispatchQueue.main.async {self.running=false}}
        }
        if start-lastSave > 5 {saveFlash();lastSave=start}
    }
    private func stateURL(_ id: String) -> URL {directory.appendingPathComponent(id).appendingPathExtension("flash")}
    private func saveFlash() {
        guard let m=machine, let id=activeID else {return}
        let n=instrument_flash(m,nil,0)
        guard n>0 && n<=4*1024*1024 else {return}
        var bytes=[UInt8](repeating:0,count:n)
        _=instrument_flash(m,&bytes,n)
        let data=Data(bytes);let digest=Data(SHA256.hash(data:data))
        guard digest != flashDigest else {return}
        do {try data.write(to:stateURL(id),options:.atomic);flashDigest=digest} catch {report(error)}
    }
}
