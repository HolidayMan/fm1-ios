import AVFoundation
import XCTest
@testable import FM1

final class AudioRingTests: XCTestCase {
    private func consume(_ ring: AudioRing, _ frames: Int) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames))!
        output.frameLength = UInt32(frames)
        ring.render(frames: UInt32(frames), output: output.mutableAudioBufferList)
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: frames))
    }
    func testBoundedRingWrapsWithoutOverwritingUnreadSamples() throws {
        let ring = try XCTUnwrap(AudioRing(capacity: 8))
        let first = (0..<10).flatMap { [Float($0), Float(-$0)] }
        XCTAssertEqual(ring.write(first, frames: 10), 8)
        XCTAssertEqual(consume(ring, 4), [0, 1, 2, 3])
        let next = (8..<12).flatMap { [Float($0), Float(-$0)] }
        XCTAssertEqual(ring.write(next, frames: 4), 4)
        XCTAssertEqual(ring.available, 8)
        XCTAssertEqual(consume(ring, 8), [4, 5, 6, 7, 8, 9, 10, 11])
        XCTAssertEqual(ring.available, 0)
        XCTAssertEqual(ring.metrics.deliveredFrames, 12)
        XCTAssertEqual(ring.metrics.underrunFrames, 0)
    }
    func testOutputUnderrunsAreMeasuredAndRecoveryContinuesAcrossCallbacks() throws {
        let ring = try XCTUnwrap(AudioRing(capacity: 128))
        XCTAssertEqual(ring.write([Float](repeating: 0.5, count: 8), frames: 4), 4)
        let missing = consume(ring, 8)
        XCTAssertEqual(Array(missing.prefix(4)), [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(missing.last, 0)
        XCTAssertEqual(ring.metrics.underrunFrames, 4)
        XCTAssertEqual(ring.metrics.underrunCallbacks, 1)
        XCTAssertEqual(ring.write([Float](repeating: 1, count: 128), frames: 64), 64)
        let first = consume(ring, 32), second = consume(ring, 32)
        XCTAssertEqual(first.first!, 1 / 64, accuracy: 0.0001)
        XCTAssertEqual(first.last!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(second.first!, 33 / 64, accuracy: 0.0001)
        XCTAssertEqual(second.last!, 1, accuracy: 0.0001)
        XCTAssertEqual(ring.metrics.outputFrames, 72)
        XCTAssertEqual(ring.metrics.deliveredFrames, 68)
        XCTAssertEqual(ring.metrics.underrunFrames, 4)
    }
    func testInvalidCapacityIsRejected() {
        XCTAssertNil(AudioRing(capacity: 0))
        XCTAssertNil(AudioRing(capacity: 3))
        XCTAssertNil(AudioRing(capacity: 65537))
    }
}
