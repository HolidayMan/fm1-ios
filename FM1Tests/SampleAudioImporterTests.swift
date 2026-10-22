import XCTest
import CryptoKit
import AVFoundation
@testable import FM1

final class SampleAudioImporterTests:XCTestCase {
    func testFSMPMatchesPinnedUpstreamCodecVector()throws {
        let input:[Int16]=[0,1000,-1000,20000,-20000,32767,-32768,7,0,1024,-2048,8192,0]
        let source=SampleAudioSource(name:"vector",samples:input.map{Float($0)/32768},sourceRate:22050,sourceChannels:1)
        let data=try SampleAudioImporter.encode(source:source,start:0,end:source.duration)
        // Independent oracle: pinned SLOOP tools/sampleio.py user_slot + FF padding.
        XCTAssertEqual(data.count,81920)
        XCTAssertEqual(data[512..<519].map{String(format:"%02x",$0)}.joined(),"707f7f2f787f0a")
        XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),"9d6134cf1c72b27bbb5c992467d754c3b884503bc13291caf3122a4ac67e8fb1")
    }
    func testTrimCapacityAndInvalidValuesAreRejected()throws {
        let source=SampleAudioSource(name:"long",samples:Array(repeating:0.2,count:22050*9),sourceRate:22050,sourceChannels:1)
        XCTAssertThrowsError(try SampleAudioImporter.encode(source:source,start:0,end:9))
        let data=try SampleAudioImporter.encode(source:source,start:1,end:2)
        XCTAssertEqual(data.prefix(4),Data("FSMP".utf8))
        XCTAssertEqual(data[6],1)
        XCTAssertThrowsError(try SampleAudioImporter.encode(source:source,start:2,end:1))
        XCTAssertThrowsError(try SampleAudioImporter.encode(source:source,start:.nan,end:2))
        XCTAssertThrowsError(try SampleAudioImporter.encode(source:source,start:0,end:2,rootNote:128))
        let invalid=SampleAudioSource(name:"invalid",samples:[.nan],sourceRate:22050,sourceChannels:1)
        XCTAssertThrowsError(try SampleAudioImporter.encode(source:invalid,start:0,end:invalid.duration))
    }
    func testWAVRoundTripResamplesStereoToMonoAndPreservesDuration()throws {
        var pcm=Data()
        for index in 0..<4410 {
            let value=Int16(sin(Double(index)*0.1)*12000)
            for sample in [value,-value] {
                let bits=UInt16(bitPattern:sample);pcm.append(UInt8(bits&255));pcm.append(UInt8(bits>>8))
            }
        }
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer {try? FileManager.default.removeItem(at:file)}
        try PCMFile.wav(pcm:pcm,sampleRate:44100,channels:2).write(to:file)
        let source=try SampleAudioImporter.load(file)
        XCTAssertEqual(source.sourceRate,44100);XCTAssertEqual(source.sourceChannels,2)
        XCTAssertEqual(source.duration,0.1,accuracy:0.005)
        XCTAssertLessThan(source.samples.map{abs($0)}.max() ?? 1,0.0001,"Stereo channels must mix rather than silently choosing one")
        let preview=try SampleAudioImporter.previewWAV(source:source,start:0,end:source.duration)
        XCTAssertEqual(preview.prefix(4),Data("RIFF".utf8));XCTAssertEqual(preview.count,44+source.samples.count*2)
    }
    func testInvalidWAVDoesNotProduceSampleData()throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer {try? FileManager.default.removeItem(at:file)}
        try Data("not a WAV".utf8).write(to:file)
        XCTAssertThrowsError(try SampleAudioImporter.load(file))
    }
    func testNormalizationHandlesSilenceAndSubnormalPeaks()throws {
        let tiny=SampleAudioSource(name:"tiny",samples:[0,.leastNonzeroMagnitude,-Float.leastNonzeroMagnitude],sourceRate:22050,sourceChannels:1)
        let expected=SampleAudioSource(name:"tiny",samples:[0,30000.0/32768,-30000.0/32768],sourceRate:22050,sourceChannels:1)
        XCTAssertEqual(try SampleAudioImporter.encode(source:tiny,start:0,end:tiny.duration,normalize:true),try SampleAudioImporter.encode(source:expected,start:0,end:expected.duration))
        let silent=SampleAudioSource(name:"silence",samples:[0,0,0],sourceRate:22050,sourceChannels:1)
        XCTAssertEqual(try SampleAudioImporter.encode(source:silent,start:0,end:silent.duration,normalize:true),try SampleAudioImporter.encode(source:silent,start:0,end:silent.duration))
    }
    func testStereoDownmixPreservesSamePhaseLevel()throws {
        var pcm=Data()
        for _ in 0..<4410 {for _ in 0..<2 {pcm.append(0);pcm.append(32)}}
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer {try? FileManager.default.removeItem(at:file)}
        try PCMFile.wav(pcm:pcm,sampleRate:44100,channels:2).write(to:file)
        let source=try SampleAudioImporter.load(file)
        let mean=source.samples.reduce(0,+)/Float(source.samples.count)
        XCTAssertEqual(mean,0.25,accuracy:0.003,"Downmix must average both channels without adding gain")
    }
    func testFrameAlignedTrimNeverAddsAnExtraFrameOrExceedsCapacity()throws {
        let source=SampleAudioSource(name:"frames",samples:Array(repeating:0.2,count:22050*12),sourceRate:22050,sourceChannels:1)
        var selection=SampleTrimSelection(frameCount:source.samples.count)
        XCTAssertTrue(selection.fits)
        XCTAssertEqual(selection.encodedBytes,81920)
        // Many positions reproduce floating point seconds-to-frame rounding edges.
        for first in stride(from:1,to:30000,by:173) {
            selection.setStart(fraction:Double(first)/Double(source.samples.count))
            selection.fit()
            let slot=try SampleAudioImporter.encode(source:source,start:selection.start,end:selection.end)
            let frames=(0..<4).reduce(0){$0 | Int(slot[36+$1]) << ($1*8)}
            XCTAssertEqual(frames,selection.count)
            XCTAssertEqual(selection.encodedBytes,512+(frames+1)/2)
        }
        selection.setEnd(fraction:1)
        XCTAssertFalse(selection.fits)
        selection.setStart(fraction:1)
        XCTAssertEqual(selection.count,1)
        selection.move(first:0)
        XCTAssertEqual(selection.count,1)
        selection.move(first:Int.max)
        XCTAssertEqual(selection.last,source.samples.count)
        XCTAssertEqual(selection.count,1)
        let before=selection
        selection.setStart(fraction:.nan);selection.setEnd(fraction:.infinity)
        XCTAssertEqual(selection,before)
    }
    func testPreviewDecodesTheImportedADPCMAndNormalization()throws {
        let source=SampleAudioSource(name:"quiet",samples:(0..<2205).map{Float(sin(Double($0)*0.12))*0.02},sourceRate:22050,sourceChannels:1)
        let plain=try SampleAudioImporter.previewWAV(source:source,start:0,end:source.duration)
        let normalized=try SampleAudioImporter.previewWAV(source:source,start:0,end:source.duration,normalize:true)
        func peak(_ wav:Data)->Int {
            stride(from:44,to:wav.count,by:2).map{abs(Int(Int16(bitPattern:UInt16(wav[$0]) | UInt16(wav[$0+1])<<8)))}.max() ?? 0
        }
        XCTAssertLessThan(peak(plain),1000)
        XCTAssertGreaterThan(peak(normalized),28000)
        XCTAssertEqual(normalized.count,44+source.samples.count*2)
        // Hand decoded IMA stream 0,7,15,7 from the pinned upstream codec vector.
        let vector=SampleAudioSource(name:"vector",samples:[0,1000,-1000,20000].map{Float($0)/32768},sourceRate:22050,sourceChannels:1)
        let preview=try SampleAudioImporter.previewWAV(source:vector,start:0,end:vector.duration)
        let decoded=stride(from:44,to:preview.count,by:2).map{Int16(bitPattern:UInt16(preview[$0]) | UInt16(preview[$0+1])<<8)}
        XCTAssertEqual(decoded,[0,11,-19,44])
    }
    func testVoiceMemoM4ADecodesUsingNativeAudioDecoder()throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        defer {try? FileManager.default.removeItem(at:url)}
        func record()throws {
            let file=try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000])
            let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4410))
            buffer.frameLength=4410
            let channel=try XCTUnwrap(buffer.floatChannelData?[0])
            for i in 0..<4410 {channel[i]=Float(sin(Double(i)*0.1))*0.3}
            try file.write(from:buffer)
        }
        try record() // Close/finalize the compressed file before decoding.
        let source=try SampleAudioImporter.load(url)
        XCTAssertEqual(source.sourceChannels,1)
        XCTAssertEqual(source.duration,0.1,accuracy:0.025)
        XCTAssertGreaterThan(source.samples.map{abs($0)}.max() ?? 0,0.1)
        XCTAssertEqual(try SampleAudioImporter.encode(source:source,start:0,end:source.duration).prefix(4),Data("FSMP".utf8))
    }
    @MainActor func testAuditionReactivatesStoppedSessionAndAdvancesPlayer()async throws {
        // Reproduce opening Files after the instrument worker has paused/deactivated audio.
        try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        let source=SampleAudioSource(name:"preview",samples:(0..<22050).map{Float(sin(Double($0)*0.12))*0.1},sourceRate:22050,sourceChannels:1)
        let audition=FM1SampleAudition()
        try audition.play(SampleAudioImporter.previewWAV(source:source,start:0,end:source.duration))
        XCTAssertTrue(audition.playing)
        XCTAssertEqual(audition.duration,1,accuracy:0.001)
        try await Task.sleep(for:.milliseconds(180))
        XCTAssertGreaterThan(audition.currentTime,0.05,"AVAudioPlayer must actually advance after session deactivation")
        let obsolete=try AVAudioPlayer(data:SampleAudioImporter.previewWAV(source:source,start:0,end:source.duration))
        audition.audioPlayerDidFinishPlaying(obsolete,successfully:true)
        await Task.yield()
        XCTAssertTrue(audition.playing,"Completion of an older player must not stop a newer preview")
        audition.stop()
        XCTAssertFalse(audition.playing)
        XCTAssertEqual(audition.currentTime,0)
    }

}
