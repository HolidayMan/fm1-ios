import XCTest
import CryptoKit
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
}
