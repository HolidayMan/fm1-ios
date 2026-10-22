import Foundation
import AVFoundation

struct SampleAudioSource:Sendable {
    let name:String
    let samples:[Float]
    let sourceRate:Double
    let sourceChannels:Int
    var duration:Double {Double(samples.count)/22050}
    var waveform:[Float] {
        guard !samples.isEmpty else{return []}
        let stride=max(1,(samples.count+255)/256)
        return Swift.stride(from:0,to:samples.count,by:stride).map {offset in
            samples[offset..<min(offset+stride,samples.count)].reduce(Float(0)){max($0,abs($1))}
        }
    }
}

enum SampleAudioImporter {
    static let slotBytes=81920, dataOffset=512, sampleRate=22050
    static let maximumFrames=(slotBytes-dataOffset)*2
    static var maximumDuration:Double {Double(maximumFrames)/Double(sampleRate)}
    private static func failure(_ message:String)->NSError {
        NSError(domain:"SampleImport",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }

    /// Decode and high-quality resample on a utility queue, never on the UI or engine worker.
    static func load(_ url:URL)throws->SampleAudioSource {
        let access=url.startAccessingSecurityScopedResource()
        defer {if access {url.stopAccessingSecurityScopedResource()}}
        let bytes=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard bytes>0,bytes<=32*1024*1024 else {throw failure("Choose a WAV file no larger than 32 MB.")}
        let handle=try FileHandle(forReadingFrom:url)
        defer {try? handle.close()}
        let header=try handle.read(upToCount:12) ?? Data()
        guard header.count==12,header.prefix(4)==Data("RIFF".utf8),header.suffix(4)==Data("WAVE".utf8) else {
            throw failure("Choose a valid WAV audio file.")
        }
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let inputFormat=file.processingFormat,rate=inputFormat.sampleRate,channels=Int(inputFormat.channelCount)
        guard rate.isFinite,(8000...192000).contains(rate),(1...2).contains(channels),file.length>0,
              Double(file.length)/rate<=120 else {throw failure("Use mono or stereo WAV audio, 8–192 kHz, up to two minutes long.")}
        guard let outputFormat=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:22050,channels:1,interleaved:false),
              let converter=AVAudioConverter(from:inputFormat,to:outputFormat),
              let input=AVAudioPCMBuffer(pcmFormat:inputFormat,frameCapacity:8192),
              let output=AVAudioPCMBuffer(pcmFormat:outputFormat,frameCapacity:8192) else {throw failure("This WAV format cannot be converted.")}
        converter.sampleRateConverterQuality=AVAudioQuality.max.rawValue
        converter.downmix=true
        var result=[Float](),readError:Error?
        result.reserveCapacity(min(Int(ceil(Double(file.length)/rate*22050))+32,22050*120+8192))
        var finished=false
        while !finished {
            var conversionError:NSError?
            let status=converter.convert(to:output,error:&conversionError) {requested,state in
                if file.framePosition>=file.length {state.pointee = .endOfStream;return nil}
                do {
                    try file.read(into:input,frameCount:min(requested,input.frameCapacity))
                    state.pointee = input.frameLength>0 ? .haveData : .endOfStream
                    return input.frameLength>0 ? input : nil
                } catch {readError=error;state.pointee = .endOfStream;return nil}
            }
            if let readError {throw readError}
            if let conversionError {throw conversionError}
            guard status != .error else {throw failure("The WAV audio could not be decoded.")}
            if let channel=output.floatChannelData?[0],output.frameLength>0 {
                for index in 0..<Int(output.frameLength) {
                    let value=channel[index]
                    guard value.isFinite else {throw failure("The WAV contains invalid audio samples.")}
                    result.append(max(-1,min(1,value)))
                }
            }
            guard result.count<=22050*120+8192 else {throw failure("The decoded WAV is too long.")}
            finished = status == .endOfStream
            if status == .inputRanDry && output.frameLength==0 {throw failure("The WAV audio is incomplete.")}
        }
        guard !result.isEmpty else {throw failure("The WAV contains no audio.")}
        return SampleAudioSource(name:url.deletingPathExtension().lastPathComponent,samples:result,sourceRate:rate,sourceChannels:channels)
    }

    private static func region(_ source:SampleAudioSource,start:Double,end:Double)throws->ArraySlice<Float> {
        guard start.isFinite,end.isFinite,start>=0,end>start,end<=source.duration+0.00001 else {throw failure("Choose a valid start and end within the sound.")}
        let first=Int((start*22050).rounded(.down)),last=min(source.samples.count,Int((end*22050).rounded(.up)))
        guard first>=0,last>first,last<=source.samples.count else {throw failure("Select a longer audio region.")}
        return source.samples[first..<last]
    }
    static func encodedByteCount(duration:Double)->Int {
        guard duration.isFinite,duration>=0,duration<=120 else{return Int.max}
        return dataOffset+(Int(ceil(duration*22050))+1)/2
    }

    /// FSMP v1, one zone, mono 22.05 kHz, low-nibble-first IMA ADPCM.
    /// Format and codec derive from SLOOP's GPL-3.0-only tools/sampleio.py;
    /// original attribution remains in NOTICE-native-sloop and the source notices.
    static func encode(source:SampleAudioSource,start:Double,end:Double,normalize:Bool=false,rootNote:Int=60)throws->Data {
        let selected=try region(source,start:start,end:end)
        guard selected.count<=maximumFrames,(0...127).contains(rootNote) else {throw failure("Trim the sound to fit the 80 KiB sample slot.")}
        let peak=selected.reduce(Float(0)){max($0,abs($1))}
        let gain:Double=normalize && peak>0 ? 30000/(32768*Double(peak)) : 1
        var encoded=Data(count:(selected.count+1)/2),predictor=0,index=0
        for (offset,value) in selected.enumerated() {
            guard value.isFinite else {throw failure("The sound contains invalid samples.")}
            let sample=Int(max(-32768,min(32767,(Double(value)*gain*32768).rounded(.towardZero))))
            let step=steps[index]
            var difference=sample-predictor,code=0,delta=step>>3
            if difference<0 {code=8;difference = -difference}
            if difference>=step {code|=4;difference-=step;delta+=step}
            if difference>=step>>1 {code|=2;difference-=step>>1;delta+=step>>1}
            if difference>=step>>2 {code|=1;delta+=step>>2}
            predictor=max(-32768,min(32767,predictor+(code&8 != 0 ? -delta : delta)))
            index=max(0,min(88,index+adjustments[code&7]))
            if offset&1==0 {encoded[offset/2]=UInt8(code)} else {encoded[offset/2]|=UInt8(code<<4)}
        }
        var slot=Data(repeating:0xff,count:slotBytes)
        slot.replaceSubrange(0..<dataOffset,with:repeatElement(UInt8(0),count:dataOffset))
        put32(0x504d5346,at:0,in:&slot);put16(1,at:4,in:&slot);slot[6]=1
        let title=source.name.uppercased().utf8.filter {32...126 ~= $0}.prefix(8)
        for (offset,byte) in title.enumerated(){slot[8+offset]=byte}
        put32(UInt32(encoded.count),at:16,in:&slot);put32(crc32(encoded),at:20,in:&slot)
        put32(0,at:32,in:&slot);put32(UInt32(selected.count),at:36,in:&slot)
        put32(0,at:40,in:&slot);put32(UInt32(selected.count-1),at:44,in:&slot)
        put32(32768,at:48,in:&slot);put16(UInt16(rootNote*16),at:52,in:&slot)
        slot[58]=127
        slot.replaceSubrange(dataOffset..<dataOffset+encoded.count,with:encoded)
        return slot
    }
    static func previewWAV(source:SampleAudioSource,start:Double,end:Double)throws->Data {
        let selected=try region(source,start:start,end:end)
        var pcm=Data(capacity:selected.count*2)
        for value in selected {
            guard value.isFinite else {throw failure("The sound contains invalid samples.")}
            let sample=Int16(max(-32768,min(32767,Int((Double(value)*32768).rounded(.towardZero)))))
            let bits=UInt16(bitPattern:sample);pcm.append(UInt8(bits&255));pcm.append(UInt8(bits>>8))
        }
        return PCMFile.wav(pcm:pcm,sampleRate:22050,channels:1)
    }
    static func crc32(_ data:Data)->UInt32 {
        var result=UInt32.max
        for byte in data {result ^= UInt32(byte);for _ in 0..<8 {result=(result>>1) ^ (result&1 != 0 ? 0xedb88320 : 0)}}
        return result ^ UInt32.max
    }
    static func put16(_ value:UInt16,at offset:Int,in data:inout Data){data[offset]=UInt8(value&255);data[offset+1]=UInt8(value>>8)}
    static func put32(_ value:UInt32,at offset:Int,in data:inout Data){for shift in 0..<4 {data[offset+shift]=UInt8((value>>UInt32(shift*8))&255)}}
    private static let adjustments=[-1,-1,-1,-1,2,4,6,8]
    private static let steps=[7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
}

enum PCMFile {
    static func wav(pcm:Data,sampleRate:Int,channels:Int)->Data {
        var header=Data(count:44)
        header.replaceSubrange(0..<4,with:Data("RIFF".utf8));header.replaceSubrange(8..<12,with:Data("WAVE".utf8))
        header.replaceSubrange(12..<16,with:Data("fmt ".utf8));header.replaceSubrange(36..<40,with:Data("data".utf8))
        SampleAudioImporter.put32(UInt32(pcm.count+36),at:4,in:&header)
        SampleAudioImporter.put32(16,at:16,in:&header);SampleAudioImporter.put16(1,at:20,in:&header)
        SampleAudioImporter.put16(UInt16(channels),at:22,in:&header);SampleAudioImporter.put32(UInt32(sampleRate),at:24,in:&header)
        SampleAudioImporter.put32(UInt32(sampleRate*channels*2),at:28,in:&header);SampleAudioImporter.put16(UInt16(channels*2),at:32,in:&header)
        SampleAudioImporter.put16(16,at:34,in:&header);SampleAudioImporter.put32(UInt32(pcm.count),at:40,in:&header)
        header.append(pcm);return header
    }
}
