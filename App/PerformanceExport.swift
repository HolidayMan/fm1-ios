import Foundation

/// Offline exports own a separate native instance on this serial worker. They
/// never advance the live instrument, write from its callback, or change its mix.
enum PerformanceExport {
    enum Mode:String,CaseIterable,Identifiable {
        case loop="Loop",song="Whole song"
        var id:String {rawValue}
    }
    // Bounds runaway or externally clocked songs; incomplete files are discarded.
    static let maximumSongSeconds=30*60
    static func exportSnapshot(_ snapshot:SloopWorkSnapshot,mode:Mode)throws->SloopWorkSnapshot {
        try snapshot.validate()
        var arrangement=try snapshot.bytes("arrangement")
        if mode == .song {
            let entries=Int(arrangement[10])
            guard (1...16).contains(entries),arrangement.count == 11+entries*2 else {throw songError("The song arrangement is invalid.")}
            for index in 0..<entries {
                let section=Int(arrangement[11+index*2]),bars=Int(arrangement[12+index*2])
                guard section<4,(1...64).contains(bars),arrangement[2] & UInt8(1<<section) != 0 else {
                    throw songError("Save every section used by the song (A–D) in SLOOP before exporting it.")
                }
            }
        }
        arrangement[3]=mode == .song ? 1 : 0
        arrangement[9]=0 // Export one pass even when repeat is enabled in the live instrument.
        var copy=snapshot
        copy.parts.removeAll{$0.name == "arrangement"}
        copy.parts.append(SloopWorkSnapshot.Part("arrangement",arrangement))
        return copy
    }
    private static func songError(_ message:String)->NSError {NSError(domain:"AudioExport",code:6,userInfo:[NSLocalizedDescriptionKey:message])}

    private static let queue=DispatchQueue(label:"fm1.performance-export",qos:.utility)
    private final class Cancellation:@unchecked Sendable {
        private let lock=NSLock()
        private var stopped=false
        func cancel(){lock.lock();stopped=true;lock.unlock()}
        func check()throws {lock.lock();let value=stopped;lock.unlock();if value {throw CancellationError()}}
    }
    static func render(snapshot:SloopWorkSnapshot,package:Data,duration:Double,tail:Double,mode:Mode = .loop,
                       progress:@escaping @Sendable(Double)->Void={_ in}) async throws->URL {
        guard duration.isFinite,tail.isFinite,(1...120).contains(duration),(0...10).contains(tail) else {
            throw NSError(domain:"AudioExport",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose 1–120 seconds of music and up to 10 seconds of effect tail."])
        }
        let cancellation=Cancellation()
        return try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {continuation in
                queue.async {
                    do {continuation.resume(returning:try renderOnWorker(snapshot:snapshot,package:package,duration:duration,tail:tail,mode:mode,cancellation:cancellation,progress:progress))}
                    catch {continuation.resume(throwing:error)}
                }
            }
        },onCancel:{cancellation.cancel()})
    }
    private static func renderOnWorker(snapshot:SloopWorkSnapshot,package:Data,duration:Double,tail:Double,mode:Mode,
                                       cancellation:Cancellation,progress:@escaping @Sendable(Double)->Void)throws->URL {
        try cancellation.check()
        let export=try exportSnapshot(snapshot,mode:mode)
        let machine=try export.nativeCreate(package:package)
        defer {instrument_destroy(machine)}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("FM1Export-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file=folder.appendingPathComponent(mode == .song ? "SLOOP-song.wav" : "SLOOP-performance.wav")
        var success=false
        defer {if !success {try? FileManager.default.removeItem(at:folder)}}
        guard FileManager.default.createFile(atPath:file.path,contents:PCMFile.wav(pcm:Data(),sampleRate:44100,channels:2)) else {
            throw NSError(domain:"AudioExport",code:2,userInfo:[NSLocalizedDescriptionKey:"There is not enough space to create the audio file."])
        }
        let writer=try FileHandle(forWritingTo:file)
        defer {try? writer.close()}
        try writer.seekToEnd()
        var samples=[Float](repeating:0,count:1024)
        func renderFrames(_ frames:Int)throws {
            let rendered=samples.withUnsafeMutableBufferPointer {instrument_render(machine,$0.baseAddress,frames)}
            guard rendered==frames else {throw NSError(domain:"AudioExport",code:3,userInfo:[NSLocalizedDescriptionKey:"The instrument could not render the complete audio file."])}
        }
        // Stop/reset before the first downbeat, applying the firmware's ordinary
        // control boundary. This preparatory silence is not written to the file.
        guard instrument_sloop_transport(machine,false) else {throw unsupported()}
        try renderFrames(512)
        guard instrument_sloop_transport(machine,true) else {throw unsupported()}
        let musicFrames=Int((duration*44100).rounded()),tailFrames=Int((tail*44100).rounded())
        var written=0
        func writeFrames(_ count:Int)throws {
            try cancellation.check()
            try renderFrames(count)
            var bytes=Data(capacity:count*4)
            for value in samples.prefix(count*2) {
                guard value.isFinite else {throw NSError(domain:"AudioExport",code:4,userInfo:[NSLocalizedDescriptionKey:"The instrument produced invalid audio. No completed file was saved."])}
                let signed=Int16(max(-32768,min(32767,Int((Double(value)*32768).rounded(.towardZero)))))
                let bits=UInt16(bitPattern:signed);bytes.append(UInt8(bits&255));bytes.append(UInt8(bits>>8))
            }
            try writer.write(contentsOf:bytes)
            written+=count
        }
        if mode == .song {
            var state=Data(count:43),started=false,lastReported=0
            while true {
                // Inspect the firmware clock, rather than estimating length from one tempo.
                // Polling quantum bounds the final boundary to less than 3 ms.
                try writeFrames(128)
                let size=state.withUnsafeMutableBytes{instrument_sloop_arrangement_read(machine,$0.bindMemory(to:UInt8.self).baseAddress,43)}
                guard size>=13 else {throw songError("Couldn’t read the song’s playback position.")}
                if state[5] != 0 {started=true}
                else if started {break}
                else if written>=44100 {throw songError("The song did not start. Check its saved sections and clock settings in SLOOP.")}
                guard written<maximumSongSeconds*44100 else {throw songError("Song export exceeded 30 minutes. Shorten the arrangement or check SLOOP’s clock settings. No partial file was kept.")}
                if written-lastReported>=4410 {
                    let index=min(Int(state[6]),Int(state[10])-1)
                    let bars=max(1,Int(state[12+index*2]))
                    progress(min(0.94,0.94*(Double(index)+Double(state[7])/Double(bars))/Double(state[10])))
                    lastReported=written
                }
            }
        } else {
            while written<musicFrames {
                try writeFrames(min(512,musicFrames-written))
                if written%44032<512 || written==musicFrames {progress(0.94*Double(written)/Double(musicFrames))}
            }
        }
        guard instrument_sloop_transport(machine,false) else {throw unsupported()}
        let musicEnd=written
        while written-musicEnd<tailFrames {
            try writeFrames(min(512,tailFrames-(written-musicEnd)))
            progress(0.94+0.06*Double(written-musicEnd)/Double(max(1,tailFrames)))
        }
        progress(1)
        try cancellation.check()
        var header=PCMFile.wav(pcm:Data(),sampleRate:44100,channels:2)
        SampleAudioImporter.put32(UInt32(written*4+36),at:4,in:&header)
        SampleAudioImporter.put32(UInt32(written*4),at:40,in:&header)
        try writer.seek(toOffset:0);try writer.write(contentsOf:header);try writer.synchronize()
        success=true;return file
    }
    private static func unsupported()->NSError {
        NSError(domain:"AudioExport",code:5,userInfo:[NSLocalizedDescriptionKey:"This instrument does not support offline audio export."])
    }
}
