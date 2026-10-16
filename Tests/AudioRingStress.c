// Host-only concurrent verification; all waiting/yielding is outside the render function.
#include "../App/AudioRing.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>

enum { total_frames = 131072, chunk = 16 };
static void *produce(void *context) {
    FM1AudioRing *ring = context;
    uint32_t produced = 0;
    while (produced < total_frames) {
        float samples[chunk * 2];
        for (uint32_t i = 0; i < chunk; ++i) {
            samples[2 * i] = (float)(produced + i + 1);
            samples[2 * i + 1] = -samples[2 * i];
        }
        uint32_t count = fm1_audio_ring_write(ring, samples, chunk);
        produced += count;
        if (!count) sched_yield();
    }
    return NULL;
}
static void *consume(void *context) {
    FM1AudioRing *ring = context;
    float samples[chunk * 2];
    AudioBufferList output = { .mNumberBuffers = 1, .mBuffers = {{ .mNumberChannels = 2,
        .mDataByteSize = sizeof(samples), .mData = samples }} };
    for (uint32_t consumed = 0; consumed < total_frames; consumed += chunk) {
        while (fm1_audio_ring_available(ring) < chunk) sched_yield();
        fm1_audio_ring_render(ring, chunk, &output);
        for (uint32_t i = 0; i < chunk; ++i) {
            assert(samples[2 * i] == (float)(consumed + i + 1));
            assert(samples[2 * i + 1] == -samples[2 * i]);
        }
    }
    return NULL;
}
int main(void) {
    assert(!fm1_audio_ring_create(0));
    assert(!fm1_audio_ring_create(3));
    for (unsigned run = 0; run < 16; ++run) {
        FM1AudioRing *ring = fm1_audio_ring_create(2048);
        assert(ring);
        pthread_t producer, consumer;
        assert(!pthread_create(&producer, NULL, produce, ring));
        assert(!pthread_create(&consumer, NULL, consume, ring));
        assert(!pthread_join(producer, NULL));
        assert(!pthread_join(consumer, NULL));
        FM1AudioRingStats stats = fm1_audio_ring_stats(ring);
        assert(stats.output_frames == total_frames);
        assert(stats.delivered_frames == total_frames);
        assert(!stats.underrun_frames && !stats.underrun_callbacks && !stats.buffered_frames);
        fm1_audio_ring_destroy(ring);
    }
    puts("SPSC stress passed: 2097152 stereo frames, exact sequence, wrap and final conservation.");
    return 0;
}
