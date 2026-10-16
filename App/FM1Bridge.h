#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
void *instrument_create(const uint8_t *, size_t, uint8_t *, size_t);
void instrument_destroy(void *);
size_t instrument_render(void *, float *, size_t);
void instrument_key(void *, uint32_t, bool);
void instrument_encoder(void *, uint32_t, int32_t);
void instrument_volume(void *, uint32_t);
uint32_t instrument_snapshot(void *, uint32_t *, float *);
size_t instrument_flash(void *, uint8_t *, size_t);
bool instrument_restore(void *, const uint8_t *, size_t);
