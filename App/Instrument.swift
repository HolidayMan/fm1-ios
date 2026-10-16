import SwiftUI
import AVFoundation
import CryptoKit
import Darwin

struct Firmware: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

/// All emulator state belongs to the worker queue. The source-node callback only
/// reads already-produced samples and signals a coalesced refill; it never emulates.
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
    @Published private(set) var audioDiagnostics = AudioDiagnostics()
    private let worker = DispatchQueue(label: "fm1.instrument", qos: .userInteractive)
    private var machine: UnsafeMutableRawPointer?
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var audioRing: AudioRing?
    private var refillSignal: DispatchSourceUserDataAdd?
    private var producerScheduled = false
    private var generation = 0
    private var playing = false
    private var activeID: String?
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
            Firmware(id: $0.deletingPathExtension().lastPathComponent, name: $0.deletingPathExtension().lastPathComponent.components(separatedBy: " · ").first ?? $0.deletingPathExtension().lastPathComponent, url: $0)
        }.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    func importFirmware(_ url: URL, removeAfterImport: Bool = false) {
        busy = true
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
                machine = next; activeID = fw.id
                if let saved = storage.sync(execute: { try? Data(contentsOf: stateURL(fw.id)) }) {
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
        let checkpointTask = CheckpointBackgroundTask()
        worker.async { [self] in
            stopWorker(); saveFlash(waitForWrite: true)
            DispatchQueue.main.async {
                self.running = false; self.status = self.selected == nil ? "Choose a firmware to begin" : "Paused"
                checkpointTask.end()
            }
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
        worker.async { [self] in workerMuted = level == 0; engine?.mainMixerNode.outputVolume = level }
    }
    private func startWorker() throws {
        guard machine != nil, !playing else {return}
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
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
        requestProduce(g)
    }
    private func stopWorker() {
        // stop() synchronizes engine rendering before taking the final counter snapshot.
        engine?.stop()
        if playing { publishDiagnostics(force: true) }
        generation += 1; playing = false; producerScheduled = false
        refillSignal?.cancel(); refillSignal = nil
        for id in 0..<41 { instrument_key(machine, UInt32(id), false) }
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
                self.screen = image; self.leds = led
                self.status = state == 2 ? "Firmware stopped — try another package" : (slow ? "Emulation is slower than real time" : "Running · 44.1 kHz")
            }
            lastSnapshot = now
            if state == 2 { stopWorker(); DispatchQueue.main.async { self.running = false }; return }
        }
        if now - lastSave > 5 { saveFlash(); lastSave = now }
        publishDiagnostics()
        // Keep producing continuously while late; never wait for a completed audio
        // buffer before starting the next emulation chunk. Yield between chunks so
        // queued keys/knobs/pause remain responsive on this same serial worker.
        if reschedule { requestProduce(g) }
    }
    private func publishDiagnostics(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastDiagnostics >= 2 else { return }
        lastDiagnostics = now
        var diagnostic = health.diagnostics(elapsed: now - playbackStart)
        diagnostic.firmware = activeID
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
        diagnostic.hardwareSampleRate = AVAudioSession.sharedInstance().sampleRate
        diagnostic.hardwareIOSeconds = AVAudioSession.sharedInstance().ioBufferDuration
        diagnostic.updatedAt = Date()
        let report = diagnostic
        DispatchQueue.main.async { self.audioDiagnostics = report }
        let url = directory.deletingLastPathComponent().appendingPathComponent("AudioDiagnostics.json")
        storage.async {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(report) { try? data.write(to: url, options: .atomic) }
        }
    }
    private func stateURL(_ id: String) -> URL {directory.appendingPathComponent(id).appendingPathExtension("flash")}
    private func saveFlash(waitForWrite: Bool = false) {
        guard let m=machine, let id=activeID else {return}
        let n=instrument_flash(m,nil,0)
        guard n>0 && n<=4*1024*1024 else {return}
        var data = Data(count: n)
        data.withUnsafeMutableBytes { bytes in
            _ = instrument_flash(m, bytes.bindMemory(to: UInt8.self).baseAddress, n)
        }
        let snapshot = data
        let url = stateURL(id)
        let persist = { [self] in
            let digest = Data(SHA256.hash(data: snapshot))
            guard digest != flashDigests[id] else { return }
            do { try snapshot.write(to: url, options: .atomic); flashDigests[id] = digest }
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

/// Local aggregate measurements only; no firmware bytes, user input or audio is recorded.
struct AudioDiagnostics: Codable, Equatable {
    var firmware: String?
    var device = ""
    var system = ""
    var updatedAt = Date()
    var elapsedSeconds: Double = 0
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
    /// Percentile over the most recent 256 buffers; a ratio above 1 exceeds real time.
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
