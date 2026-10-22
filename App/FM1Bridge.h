#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
void *instrument_create(const uint8_t *, size_t, uint8_t *, size_t);
void instrument_destroy(void *);
uint32_t instrument_backend(const void *);
uint32_t instrument_workload_metrics(void *, uint64_t *, uint32_t);
size_t instrument_render(void *, float *, size_t);
void instrument_key(void *, uint32_t, bool);
void instrument_release_all(void *);
void instrument_encoder(void *, uint32_t, int32_t);
void instrument_volume(void *, uint32_t);
uint32_t instrument_snapshot(void *, uint32_t *, float *);
size_t instrument_flash(void *, uint8_t *, size_t);
bool instrument_restore(void *, const uint8_t *, size_t);

#include "AudioRing.h"

uint32_t instrument_native_kind_for_fwsc(const uint8_t *data, size_t len);
uint32_t instrument_native_kind(const void *);
uint32_t instrument_native_kind_for_sha256(const uint8_t *data, size_t len);

// Exact SLOOP typed file bridge; -1 unsupported/invalid boundary, source return codes otherwise.
int32_t instrument_sloop_object_read(void *,uint32_t,uint8_t *,size_t);
int32_t instrument_sloop_object_write(void *,uint32_t,const uint8_t *,size_t);
int32_t instrument_sloop_arrangement_read(void *,uint8_t *,size_t);
int32_t instrument_sloop_arrangement_write(void *,const uint8_t *,size_t);
int32_t instrument_sloop_sample_read(void *,uint32_t,uint8_t *,size_t);
int32_t instrument_sloop_sample_write(void *,uint32_t,const uint8_t *,size_t);
bool instrument_sloop_transport(void *,bool);

int32_t instrument_sloop_commit(void *m);

// Immutable build policy: store archives must report false.
bool instrument_research_enabled(void);

// Candidate-only SAMPLE engine/USR selection, then explicit commit.
int32_t instrument_sloop_sample_assign(void *,uint32_t,uint32_t);
