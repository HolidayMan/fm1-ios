#ifndef FM1_THREADED_ENGINE_H
#define FM1_THREADED_ENGINE_H
#include <stdint.h>
typedef struct { uint8_t tag, a, b, c; uint32_t imm, aux, next; } Fm1ThreadOp;
typedef struct Fm1ThreadState Fm1ThreadState;
typedef uint64_t (*Fm1ThreadKernel)(Fm1ThreadState *);
typedef struct { uint32_t pc, start, len, hot; Fm1ThreadKernel kernel; } Fm1ThreadBlock;
typedef struct Fm1ThreadState {
    uint32_t *regs, *flags, *sp, *rets;
    uint8_t *ram;
    const uint8_t *ram_code, *xip;
    const Fm1ThreadOp *ops;
    const Fm1ThreadBlock *blocks;
    const uint32_t *map;
    uint32_t ram_base, ram_len, xip_base, xip_len, map_mask, block_count;
    uint32_t pc, block, index, retired, budget, max_ops, status;
    void *cpu, *bus;
    uint32_t (*helper)(struct Fm1ThreadState *);
    uint32_t ticks_spent, prepaid, limit;
    void *panic;
} Fm1ThreadState;
void fm1_threaded_run(Fm1ThreadState *state);
uint64_t fm1_threaded_layout(void);
Fm1ThreadKernel fm1_threaded_bind(uint32_t pc, const Fm1ThreadOp *ops, const uint8_t *meta, uint32_t length);
#endif
