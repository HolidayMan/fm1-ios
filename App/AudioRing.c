#include "AudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct FM1AudioRing {
    _Alignas(64) _Atomic uint64_t written;
    _Alignas(64) _Atomic uint64_t read;
    _Alignas(64) _Atomic uint64_t output_frames;
    _Atomic uint64_t delivered_frames;
    _Atomic uint64_t underrun_frames;
    _Atomic uint64_t underrun_callbacks;
    uint32_t capacity;
    uint32_t recovery;
    float last_left, last_right;
    float *samples;
};

FM1AudioRing *fm1_audio_ring_create(uint32_t capacity) {
    if (!capacity || (capacity & (capacity - 1))) return NULL;
    FM1AudioRing *ring = NULL;
    if (posix_memalign((void **)&ring, 64, sizeof(*ring))) return NULL;
    memset(ring, 0, sizeof(*ring));
    atomic_init(&ring->written, 0); atomic_init(&ring->read, 0);
    atomic_init(&ring->output_frames, 0); atomic_init(&ring->delivered_frames, 0);
    atomic_init(&ring->underrun_frames, 0); atomic_init(&ring->underrun_callbacks, 0);
    if (!atomic_is_lock_free(&ring->written) || !atomic_is_lock_free(&ring->read)) { free(ring); return NULL; }
    ring->samples = calloc((size_t)capacity * 2, sizeof(float));
    if (!ring->samples) { free(ring); return NULL; }
    ring->capacity = capacity;
    return ring;
}
void fm1_audio_ring_destroy(FM1AudioRing *ring) {
    if (!ring) return;
    free(ring->samples); free(ring);
}
uint32_t fm1_audio_ring_available(const FM1AudioRing *ring) {
    // Called on the producer: its own written index is stable during this read.
    uint64_t written = atomic_load_explicit(&ring->written, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
    return (uint32_t)(written - read);
}
uint32_t fm1_audio_ring_write(FM1AudioRing *ring, const float *stereo, uint32_t frames) {
    uint64_t written = atomic_load_explicit(&ring->written, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
    uint32_t free_frames = ring->capacity - (uint32_t)(written - read);
    uint32_t count = frames < free_frames ? frames : free_frames;
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t slot = (uint32_t)(written + i) & (ring->capacity - 1);
        ring->samples[2 * slot] = stereo[2 * i];
        ring->samples[2 * slot + 1] = stereo[2 * i + 1];
    }
    atomic_store_explicit(&ring->written, written + count, memory_order_release);
    return count;
}
void fm1_audio_ring_render(FM1AudioRing *ring, uint32_t frames, AudioBufferList *output) {
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_relaxed);
    uint64_t written = atomic_load_explicit(&ring->written, memory_order_acquire);
    uint64_t available = written - read;
    uint32_t count = available < frames ? (uint32_t)available : frames;
    uint32_t fade_out = frames - count < 64 ? frames - count : 64;
    float tail_left = ring->last_left, tail_right = ring->last_right;
    for (uint32_t i = 0; i < frames; ++i) {
        float left = 0, right = 0;
        if (i < count) {
            uint32_t slot = (uint32_t)(read + i) & (ring->capacity - 1);
            left = ring->samples[2 * slot]; right = ring->samples[2 * slot + 1];
            if (ring->recovery) {
                float gain = (float)(65 - ring->recovery) / 64;
                left *= gain; right *= gain; --ring->recovery;
            }
            tail_left = left; tail_right = right;
        } else if (i - count < fade_out) {
            float gain = 1 - (float)(i - count + 1) / (float)fade_out;
            left = tail_left * gain; right = tail_right * gain;
        }
        // AVAudioSourceNode is configured for noninterleaved stereo. Also support
        // interleaved output for standalone ring verification.
        if (output->mNumberBuffers == 1 && output->mBuffers[0].mNumberChannels == 2) {
            float *data = output->mBuffers[0].mData;
            data[2 * i] = left; data[2 * i + 1] = right;
        } else {
            for (uint32_t channel = 0; channel < output->mNumberBuffers; ++channel) {
                float *data = output->mBuffers[channel].mData;
                data[i] = channel == 0 ? left : right;
            }
        }
        ring->last_left = left; ring->last_right = right;
    }
    // Publish only after every sample has been read; producer cannot overwrite
    // unread data while the callback is deinterleaving it.
    atomic_store_explicit(&ring->read, read + count, memory_order_release);
    atomic_fetch_add_explicit(&ring->output_frames, frames, memory_order_relaxed);
    atomic_fetch_add_explicit(&ring->delivered_frames, count, memory_order_relaxed);
    if (count < frames) {
        ring->recovery = 64;
        atomic_fetch_add_explicit(&ring->underrun_frames, frames - count, memory_order_relaxed);
        atomic_fetch_add_explicit(&ring->underrun_callbacks, 1, memory_order_relaxed);
    }
}
FM1AudioRingStats fm1_audio_ring_stats(const FM1AudioRing *ring) {
    return (FM1AudioRingStats) {
        .output_frames = atomic_load_explicit(&ring->output_frames, memory_order_relaxed),
        .delivered_frames = atomic_load_explicit(&ring->delivered_frames, memory_order_relaxed),
        .underrun_frames = atomic_load_explicit(&ring->underrun_frames, memory_order_relaxed),
        .underrun_callbacks = atomic_load_explicit(&ring->underrun_callbacks, memory_order_relaxed),
        .buffered_frames = fm1_audio_ring_available(ring),
    };
}
