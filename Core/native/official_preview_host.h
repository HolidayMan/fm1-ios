/* FM1 Open V14 native build adapter; upstream APP GPLv3 + linking exception. */
#ifndef FM1_OFFICIAL_HOST_H
#define FM1_OFFICIAL_HOST_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
void *ofp_alloc(size_t);
void *ofp_calloc(size_t,size_t);
void ofp_free(void *);
#define malloc ofp_alloc
#define calloc ofp_calloc
#define free ofp_free
#pragma clang section bss="__DATA,__ofpbss" data="__DATA,__ofpdata"
#endif
