#ifndef FM1_AUDIO_RING_H
#define FM1_AUDIO_RING_H
#include <stdbool.h>
#include <stdint.h>
#include <AudioToolbox/AudioToolbox.h>

// One serial emulator producer and one audio-render consumer. No locks, allocation,
// dispatch, interpreter or filesystem calls occur in fm1_audio_ring_render.
typedef struct FM1AudioRing FM1AudioRing;
typedef struct {
    uint64_t output_frames;
    uint64_t delivered_frames;
    uint64_t underrun_frames;
    uint64_t underrun_callbacks;
    uint32_t buffered_frames;
} FM1AudioRingStats;
FM1AudioRing *fm1_audio_ring_create(uint32_t capacity);
void fm1_audio_ring_destroy(FM1AudioRing *ring);
uint32_t fm1_audio_ring_available(const FM1AudioRing *ring);
uint32_t fm1_audio_ring_write(FM1AudioRing *ring, const float *stereo, uint32_t frames);
void fm1_audio_ring_render(FM1AudioRing *ring, uint32_t frames, AudioBufferList *output);
FM1AudioRingStats fm1_audio_ring_stats(const FM1AudioRing *ring);
#endif
