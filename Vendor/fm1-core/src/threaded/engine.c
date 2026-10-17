// Statically compiled interpreter. No executable allocation or generated machine code.
#include "engine.h"
#include <string.h>
#include <stddef.h>
enum {
#define OP(name) T_##name,
#include "ops.def"
#undef OP
    T_COUNT
};
_Static_assert(sizeof(Fm1ThreadOp) == 16, "compact decoded operation layout");
_Static_assert(sizeof(Fm1ThreadBlock) == 24, "cached block layout");
uint64_t fm1_threaded_layout(void) {
    return ((uint64_t)sizeof(Fm1ThreadState) << 32) | (sizeof(Fm1ThreadBlock) << 16) | sizeof(Fm1ThreadOp);
}
const uint32_t *fm1_threaded_offsets(uint32_t *length) {
    static const uint32_t offsets[] = {offsetof(Fm1ThreadState,regs),offsetof(Fm1ThreadState,flags),offsetof(Fm1ThreadState,sp),offsetof(Fm1ThreadState,rets),offsetof(Fm1ThreadState,ram),offsetof(Fm1ThreadState,ram_code),offsetof(Fm1ThreadState,xip),offsetof(Fm1ThreadState,ops),offsetof(Fm1ThreadState,blocks),offsetof(Fm1ThreadState,map),offsetof(Fm1ThreadState,ram_base),offsetof(Fm1ThreadState,ram_len),offsetof(Fm1ThreadState,xip_base),offsetof(Fm1ThreadState,xip_len),offsetof(Fm1ThreadState,map_mask),offsetof(Fm1ThreadState,block_count),offsetof(Fm1ThreadState,pc),offsetof(Fm1ThreadState,block),offsetof(Fm1ThreadState,index),offsetof(Fm1ThreadState,retired),offsetof(Fm1ThreadState,budget),offsetof(Fm1ThreadState,max_ops),offsetof(Fm1ThreadState,status),offsetof(Fm1ThreadState,cpu),offsetof(Fm1ThreadState,bus),offsetof(Fm1ThreadState,helper),offsetof(Fm1ThreadState,ticks_spent),offsetof(Fm1ThreadState,prepaid),offsetof(Fm1ThreadState,limit),offsetof(Fm1ThreadState,panic)};
    *length = sizeof(offsets)/sizeof(offsets[0]); return offsets;
}
static inline uint32_t word(const uint8_t *p) { uint32_t v; memcpy(&v,p,4); return v; }
static inline void put_word(uint8_t *p, uint32_t v) { memcpy(p,&v,4); }
static inline uint32_t add(uint32_t a, uint32_t b, uint32_t cin, uint32_t *flags) {
    uint64_t wide = (uint64_t)a + b + cin;
    uint32_t r = (uint32_t)wide;
    *flags = (r >> 31) | ((uint32_t)(wide >> 32) << 1) | ((r == 0) << 2) | ((((a ^ r) & (b ^ r)) >> 31) << 3);
    return r;
}
static inline uint32_t alu(uint32_t op, uint32_t a, uint32_t b, uint32_t *flags) {
    switch (op) {
        case 0: return add(a,b,0,flags); case 1: return add(a,~b,1,flags); case 2: return add(b,~a,1,flags);
        case 3: return a & b; case 4: return a & ~b; case 5: return a | b; case 6: return a ^ b;
        case 7: return a * b; case 8: return a << (b & 31); case 9: return a >> (b & 31);
        default: return (uint32_t)((int32_t)a >> (b & 31));
    }
}
static inline int compare(uint8_t cond, uint32_t a, uint32_t b) {
    switch (cond) {
        case 0: return a == b; case 1: return a != b; case 2: return a < b; case 3: return a > b;
        case 4: return a <= b; case 5: return a >= b; case 6: return (int32_t)a < (int32_t)b;
        case 7: return (int32_t)a > (int32_t)b; case 8: return (int32_t)a <= (int32_t)b;
        default: return (int32_t)a >= (int32_t)b;
    }
}
static inline uint32_t rhs(Fm1ThreadState *s, uint8_t kind, uint32_t v) {
    return kind == 0 ? s->regs[v & 15] : kind == 1 ? v : 1u << (s->regs[v & 15] & 31);
}
// Exact Soc fast-memory semantics. In particular halfword reads ignore address bit zero.
// Anything that could observe peripheral time or invalidate cached code exits to Rust first.
static inline int read_mem(Fm1ThreadState *s, uint32_t addr, uint8_t spec, uint32_t *value) {
    uint32_t width = spec & 7, o = addr - s->ram_base;
    const uint8_t *p = NULL;
    if (width == 1 && o < s->ram_len) p = s->ram + o;
    else {
        uint32_t aligned = width == 4 ? addr : addr & ~3u;
        o = aligned - s->ram_base;
        if (s->ram_len >= 4 && o <= s->ram_len - 4) p = s->ram + o;
        else {
            o = aligned - s->xip_base;
            if (s->xip_len >= 4 && o <= s->xip_len - 4) p = s->xip + o;
            else return 0;
        }
        if (width == 1) p += addr & 3;
        if (width == 2) p += addr & 2;
    }
    uint32_t v;
    if (width == 1) v = *p;
    else if (width == 2) { uint16_t h; memcpy(&h,p,2); v = h; }
    else v = word(p);
    if (spec & 8) { if (width == 1) v = (uint32_t)(int32_t)(int8_t)v; else if (width == 2) v = (uint32_t)(int32_t)(int16_t)v; }
    *value = v; return 1;
}
static inline uint8_t *store_ptr(Fm1ThreadState *s, uint32_t addr, uint32_t width) {
    uint32_t o = addr - s->ram_base;
    if (width == 2 && (addr & 1)) return NULL;
    if (s->ram_len < width || o > s->ram_len - width || !s->ram_code || s->ram_code[o >> 2]) return NULL;
    return s->ram + o;
}
static inline void store(uint8_t *p, uint32_t v, uint32_t width) {
    if (width == 1) *p = (uint8_t)v;
    else if (width == 2) { uint16_t h = (uint16_t)v; memcpy(p,&h,2); }
    else put_word(p,v);
}
#include "static_kernels.inc"
void fm1_threaded_run(Fm1ThreadState *s) {
    static const void *const labels[] = {
#define OP(name) &&op_##name,
#include "ops.def"
#undef OP
    };
    uint32_t *r = s->regs, *flags = s->flags;
    uint32_t max_ops = s->max_ops;
    const uint32_t budget = s->budget;
    uint32_t count = 0, pc = s->pc, block = s->block;
    const Fm1ThreadOp *op = s->ops + s->blocks[block].start;
    const Fm1ThreadOp *begin = op;
    const Fm1ThreadOp *end = op + s->blocks[block].len;
    const Fm1ThreadOp *stop = op + (s->blocks[block].len < max_ops ? s->blocks[block].len : max_ops);
#define DISPATCH() do { if (op == stop) goto at_stop; void *target = (void *)labels[op->tag]; asm volatile("" : "+r"(target) : "i"(__COUNTER__)); goto *target; } while (0)
#define NEXT() do { ++op; DISPATCH(); } while (0)
#define JUMP(target) do { pc = (target); count += (uint32_t)(op-begin)+1; goto boundary; } while (0)
    block_entry:
        if (s->blocks[block].kernel && max_ops-count >= s->blocks[block].len) {
            uint64_t result=s->blocks[block].kernel(s);
            uint32_t n=(uint32_t)(result>>32);pc=(uint32_t)result;
            if (n==s->blocks[block].len) {count+=n;goto boundary;}
            op=begin+n;
        }
    DISPATCH();
    op_EXIT: goto partial;
    op_NOP: NEXT();
    op_MOV: r[op->a] = r[op->b]; NEXT();
    op_MOVI: r[op->a] = op->imm; NEXT();
    op_ADDI: r[op->a] = add(r[op->b],op->imm,0,flags); NEXT();
    op_ADDR: r[op->a] = add(r[op->b],r[op->c],0,flags); NEXT();
    op_SUBR: r[op->a] = add(r[op->b],~r[op->c],1,flags); NEXT();
    op_ANDI: r[op->a] = r[op->b] & op->imm; NEXT();
    op_ANDBIT: r[op->a] = r[op->b] & (1u << (r[op->c] & 31)); NEXT();
    op_SHLR: r[op->a] = r[op->b] << (r[op->c] & 31); NEXT();
    op_SHRR: r[op->a] = r[op->b] >> (r[op->c] & 31); NEXT();
    op_SHRI: r[op->a] = r[op->b] >> op->imm; NEXT();
    op_MULI: r[op->a] = r[op->b] * op->imm; NEXT();
    op_SHLI: r[op->a] = r[op->b] << op->imm; NEXT();
    op_SARI: r[op->a] = (uint32_t)((int32_t)r[op->b] >> op->imm); NEXT();
    op_ALUR: r[op->a] = alu(op->imm,r[op->b],r[op->c],flags); NEXT();
    op_ALUI: r[op->a] = alu(op->c,r[op->b],op->imm,flags); NEXT();
    op_LOAD: {
        uint32_t a = (op->b == 16 ? *s->sp : r[op->b]) + op->imm, v;
        if (!read_mem(s,a,op->c,&v)) goto op_RUST;
        r[op->a] = v; NEXT();
    }
    op_LOADIDX: {
        uint32_t a = r[op->b] + (r[op->c] << (op->imm & 31)), v;
        if (!read_mem(s,a,(uint8_t)(op->imm >> 8),&v)) goto op_RUST;
        r[op->a] = v; NEXT();
    }
    op_STORE: {
        uint32_t a = (op->b == 16 ? *s->sp : r[op->b]) + op->imm;
        uint8_t *p = store_ptr(s,a,op->c); if (!p) { if (a-s->ram_base >= s->ram_len) goto op_RUST; goto partial; }
        store(p,r[op->a],op->c); NEXT();
    }
    op_STOREIDX: {
        uint32_t a = r[op->b] + (r[op->c] << (op->imm & 31)), w = op->imm >> 8;
        uint8_t *p = store_ptr(s,a,w); if (!p) goto partial;
        store(p,r[op->a],w); NEXT();
    }
    op_STOREPOST: {
        uint32_t a = r[op->b]; uint8_t *p = store_ptr(s,a,op->c); if (!p) { if (a-s->ram_base >= s->ram_len) goto op_RUST; goto partial; }
        store(p,r[op->a],op->c); r[op->b] = a + op->imm; NEXT();
    }
    op_BRI: JUMP(compare(op->c,r[op->a],op->imm) ? op->aux : op->next);
    op_BRR: JUMP(compare(op->c,r[op->a],r[op->b]) ? op->aux : op->next);
    op_BITBR: JUMP(((r[op->a] & rhs(s,op->b,op->imm)) != 0) == op->c ? op->aux : op->next);
    op_DECBR: { uint32_t v = r[op->a] - 1; r[op->a] = v; JUMP(compare(op->c,v,op->imm) ? op->aux : op->next); }
    op_GOTO: JUMP(op->aux);
    op_CALL: *s->rets = op->next; JUMP(op->aux);
    op_RTS: JUMP(*s->rets);
    op_PUSHRET: {
        uint32_t a = *s->sp - 4; uint8_t *p = store_ptr(s,a,4); if (!p) goto partial;
        put_word(p,*s->rets); *s->sp = a; NEXT();
    }
    op_POPRET: {
        uint32_t v; if (!read_mem(s,*s->sp,4,&v)) goto partial;
        *s->sp += 4; JUMP(v);
    }
    op_POPRETS: {
        uint32_t v; if (!read_mem(s,*s->sp,4,&v)) goto partial;
        *s->sp += 4; *s->rets = v; NEXT();
    }
    op_BITEXT: {
        uint32_t v = r[op->b] >> op->imm, n = op->aux;
        if (n) v = op->c ? (uint32_t)((int32_t)(v << (32-n)) >> (32-n)) : v & ((1u << n)-1);
        r[op->a] = v; NEXT();
    }
    op_PUSH: {
        uint32_t n = op->imm, top = n > 3 ? n : 3, bot = n < 4 ? n : 4;
        uint32_t words = top - bot + 2, old = *s->sp;
        for (uint32_t k = 1; k <= words; ++k) if (!store_ptr(s,old - 4*k,4)) goto partial;
        uint32_t addr = old - 4; put_word(store_ptr(s,addr,4),*s->rets);
        for (uint32_t k = top + 1; k-- > bot;) { addr -= 4; put_word(store_ptr(s,addr,4),r[k]); }
        *s->sp = addr; NEXT();
    }
    op_POP: {
        uint32_t n = op->imm, top = n > 3 ? n : 3, bot = n < 4 ? n : 4;
        uint32_t values[17], words = top - bot + 2, addr = *s->sp;
        for (uint32_t k = 0; k < words; ++k) if (!read_mem(s,addr + 4*k,4,&values[k])) goto partial;
        for (uint32_t k = bot; k <= top; ++k) r[k] = values[k-bot];
        *s->sp = addr + 4*words; JUMP(values[words-1]);
    }
    op_SPADD: *s->sp += op->imm; NEXT();
    op_SPFROM: *s->sp = r[op->a]; NEXT();
    op_RFROMSP: r[op->a] = *s->sp + op->imm; NEXT();
    op_IFCMP: JUMP(compare(op->c,r[op->a],rhs(s,op->b,op->imm)) ? op->next : op->aux);
    op_IFBIT: JUMP((((r[op->a] & rhs(s,op->b,op->imm)) != 0) == op->c) ? op->next : op->aux);
    op_MEMADDI: {
        uint32_t a = r[op->a] + op->aux, v; uint8_t *p = store_ptr(s,a,4);
        if (!p || !read_mem(s,a,4,&v)) goto partial;
        put_word(p,v + op->imm); NEXT();
    }
    op_RUST: {
        if (s->blocks[block].pc < 0x02000000u || s->blocks[block].pc >= 0x04000000u) goto partial;
        s->retired = count + (uint32_t)(op-begin); s->index = (uint32_t)(op-s->ops);
        uint32_t target = s->helper(s);
        if (s->panic) { count = s->retired; pc = op == begin ? s->blocks[block].pc : op[-1].next; s->status = 2; goto save; }
        r = s->regs; flags = s->flags; max_ops = s->max_ops;
        uint32_t remaining = max_ops-count, length = (uint32_t)(end-begin);
        stop = begin + (remaining < length ? remaining : length);
        if (target != op->next) JUMP(target);
        NEXT();
    }
    at_stop:
        if (op != end) goto partial;
        pc = op[-1].next; count += (uint32_t)(op-begin);
    boundary:
        if (count >= budget || count == max_ops) goto complete;
        // Only immutable XIP targets chain here. RAM entries return through Rust's version guard.
        if (pc < 0x02000000u || pc >= 0x04000000u) goto complete;
        { uint32_t hit = s->map[(pc >> 1) & s->map_mask];
          if (!hit || hit > s->block_count) goto complete;
          const Fm1ThreadBlock *b = s->blocks + hit - 1;
          if (b->pc != pc || !b->hot) goto complete;
          block = hit - 1; op = s->ops + b->start; begin = op; end = op + b->len;
          uint32_t remaining = max_ops-count;
          stop = op + (b->len < remaining ? b->len : remaining);
        }
        goto block_entry;
    partial:
        count += (uint32_t)(op-begin);
        pc = op == s->ops + s->blocks[block].start ? s->blocks[block].pc : op[-1].next;
        s->status = 1; s->index = (uint32_t)(op - s->ops); goto save;
    complete:
        s->status = 0; s->index = 0;
    save:
        s->retired = count; s->pc = pc; s->block = block;
#undef DISPATCH
#undef NEXT
#undef JUMP
}
