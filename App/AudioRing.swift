import AVFoundation

struct AudioRingMetrics {
    let outputFrames, deliveredFrames, underrunFrames, underrunCallbacks: UInt64
    let bufferedFrames: Int
}

/// Its lifetime is captured by AVAudioSourceNode, so stopping/replacing the engine
/// cannot free sample memory while an old render callback still holds the node.
final class AudioRing {
    let capacity: Int
    private let pointer: OpaquePointer
    init?(capacity: Int) {
        guard capacity > 0, capacity <= 65536,
              let pointer = fm1_audio_ring_create(UInt32(capacity)) else { return nil }
        self.capacity = capacity; self.pointer = pointer
    }
    deinit { fm1_audio_ring_destroy(pointer) }
    var available: Int { Int(fm1_audio_ring_available(pointer)) }
    func write(_ samples: [Float], frames: Int) -> Int {
        guard frames >= 0, samples.count >= frames * 2 else { return 0 }
        return samples.withUnsafeBufferPointer { Int(fm1_audio_ring_write(pointer, $0.baseAddress, UInt32(frames))) }
    }
    // Called exclusively by AVAudioSourceNode's single consumer. C performs bounded
    // copies, interpolation and lock-free atomic operations; no emulator or allocation.
    func render(frames: UInt32, output: UnsafeMutablePointer<AudioBufferList>) {
        fm1_audio_ring_render(pointer, frames, output)
    }
    var metrics: AudioRingMetrics {
        let value = fm1_audio_ring_stats(pointer)
        return AudioRingMetrics(outputFrames: value.output_frames, deliveredFrames: value.delivered_frames,
                                underrunFrames: value.underrun_frames, underrunCallbacks: value.underrun_callbacks,
                                bufferedFrames: Int(value.buffered_frames))
    }
}
