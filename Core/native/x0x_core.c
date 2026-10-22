/* SPDX-License-Identifier: GPL-3.0-only
 * Native adapter derived from pinned X0X host/x0x_host.c; full sound/app sources compile separately. */
#define X0X_HOST 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <time.h>
#if 0
#include <libproc.h>
#include <unistd.h>
#endif
#define __attribute__(x)
#include "felucca_core_api.h"

/* ------------------------------------------------------------ screen --- */
static uint16_t fb[240 * 240];          /* RGB565, byte-swapped as the panel takes it (gfx.c) */
static void lcd_sync(void) {}
static void lcd_fill(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint16_t c)
{
    uint32_t i, j;
    uint16_t sc = (uint16_t)(((c >> 8) & 0xFFu) | ((c & 0xFFu) << 8));
    for (j = y; j < y + h && j < 240u; j++)
        for (i = x; i < x + w && i < 240u; i++)
            fb[j * 240u + i] = sc;
}
static uint32_t blits;
static void lcd_blit(uint32_t x, uint32_t y, uint32_t w, uint32_t h, const uint16_t *px)
{
    uint32_t i, j;
    blits++;
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++)
            if (x + i < 240u && y + j < 240u)
                fb[(y + j) * 240u + x + i] = px[j * w + i];
}
#include "../upstream/firmware/src/gfx.c"

/* ---------------------------------------------------------- platform --- */
#include "../upstream/firmware/src/app/plat.h"

static uint32_t now_ms, held_btn, held_keys, master = 2048;
static int32_t enc_acc[NE];
static uint32_t lit_btn, lit_keys, dim_keys;

uint32_t plat_ms(void) { return now_ms; }
uint32_t plat_buttons(void) { return held_btn; }
uint32_t plat_keys(void) { return held_keys; }
int32_t plat_enc(int role)
{
    int32_t v = enc_acc[role];
    enc_acc[role] = 0;
    return v;
}
uint32_t plat_master(void) { return master; }
int plat_battery(void) { return 3; }    /* the simulator: a full battery */
void plat_leds(uint32_t b, uint32_t k)
{
    lit_btn = b;
    lit_keys = k;
}
static int glow_on = 1;                 /* the device's button glow (plat_glow); the lights printed are the bright ones */
void plat_glow(int on) { glow_on = on; }
void plat_play_red(int red) { (void)red; }
void plat_keys_dim(uint32_t k) { dim_keys = k; }      /* dim keys: "o" in the leds print */      /* the device's PLAY colour: green, red while recording */

#define MQ 256
static uint32_t min_q[MQ], mi_w, mi_r;
static FILE *midi_log;
int plat_midi_in(uint32_t *pkt)
{
    if (mi_r == mi_w)
        return 0;
    *pkt = min_q[mi_r++ % MQ];
    return 1;
}
static uint32_t midi_out_count, clock_out_count, note_ons;
void plat_midi_out(uint32_t pkt)
{
    midi_out_count++;
    if ((((pkt >> 8) & 0xF0) == 0x90) && ((pkt >> 24) & 0x7F))
        note_ons++;                                  /* the notes the sequence sent (expect noteons) */
    if (((pkt >> 8) & 0xFF) == 0xF8)
        clock_out_count++;
    else if (midi_log)
        fprintf(midi_log, "%u ms: %02X %02X %02X\n", now_ms, (pkt >> 8) & 0xFF, (pkt >> 16) & 0xFF, (pkt >> 24) & 0xFF);
}

#define HOST_FLASH_SIZE 0x100000u
static uint8_t host_flash[HOST_FLASH_SIZE];
/* Full physical NOR image: source storage keeps its original A/B maps and CRCs. */
static uint8_t flash_ok = 1;
static int st_read(uint32_t off, void *dst, uint32_t n) {
    if (off > HOST_FLASH_SIZE || n > HOST_FLASH_SIZE - off) return -1;
    memcpy(dst, host_flash + off, n); return 0;
}
static int st_erase(uint32_t off) {
    off &= ~4095u; if (off > HOST_FLASH_SIZE - 4096u) return -8;
    memset(host_flash + off, 0xFF, 4096); return 0;
}
static int st_prog(uint32_t off, const void *src, uint32_t n) {
    if (off > HOST_FLASH_SIZE || n > HOST_FLASH_SIZE - off) return -8;
    const uint8_t *p = src; for (uint32_t i=0;i<n;i++) host_flash[off+i] &= p[i]; return 0;
}
#include "../upstream/firmware/src/storage.c"
int plat_store_load(uint32_t o,void*d,uint32_t n) {return st_load(o,d,n);}
int plat_store_save(uint32_t o,const void*d,uint32_t n) {return st_save(o,d,n);}
int plat_store_load_prev(uint32_t o,void*d,uint32_t n) {return st_load_prev(o,d,n);}
#define SMP_USER_XIP(k) ((const uint8_t *)(host_flash + (SMP_USER_BASE + (k) * SMP_USER_SIZE)))
#include "../upstream/firmware/src/app/slots.c"
int plat_slot_zones(int k) { return (k >= 0 && k < SMP_USER_SLOTS) ? usr_nz[k] : 0; }

const uint8_t *plat_slot(int k, int z, uint32_t *nsamples, uint32_t *rate, char name[9])
{
    const smp_user_hdr_t *h;
    uint32_t i;
    if (k < 0 || k >= SMP_USER_SLOTS || z < 0 || z >= usr_nz[k])
        return 0;
    h = (const smp_user_hdr_t *)smp_user_xip((uint32_t)k);
    for (i = 0; i < 8u; i++)
        name[i] = h->name[i] >= 32 && h->name[i] < 127 ? h->name[i] : 0;
    name[8] = 0;
    *nsamples = h->zone[z].n;
    *rate = (h->zone[z].rate * 44100u + 32768u) >> 16;
    return smp_user_xip((uint32_t)k) + SMP_USER_DATA + h->zone[z].off;
}

static uint32_t cpu_pct, cpu_peak;
static int load_force = -1;                      /* script "load N": the guard sees N%, -1 measured */
/* the second core, simulated: a job runs at once, in order (the split path, the same sums) */
static int cpu2_on;
int plat_cpu2_set(int on) { cpu2_on = on; return 0; }
int plat_cpu2_on(void) { return cpu2_on; }
int plat_cpu2_run(void (*fn)(uint32_t), uint32_t arg)
{
    if (!cpu2_on)
        return 0;
    fn(arg);
    return 1;
}
int plat_cpu2_wait(void) { return 0; }
int plat_cpu2_gave_up(void) { return 0; }
uint32_t plat_cpu2_bad(void) { return 0; }
int plat_cpu2_barred(void) { return 0; }
int plat_vdc14_mv(void) { return 1600; }
int plat_sysvdd_mv(void) { return 1380; }
static int host_crash;                            /* "fakecrash": PERF shows a crash record */
int plat_last_crash(uint32_t v[5])
{
    static const uint32_t r[5] = {1, 0x03000470u, 0, 0x00001000u, 0x02007D80u};   /* fm1-x0x#21's first */
    for (int i = 0; i < 5; i++)
        v[i] = r[i];
    return host_crash;
}
uint32_t plat_cpu_pct(void) { return cpu_pct; }
uint32_t plat_xruns(void) { return 0; }
/* performance: no CPU counter here: the "cycles" are nanoseconds (plat_cycles_hz) */
static uint64_t host_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000u + (uint64_t)t.tv_nsec;
}
void plat_perf_init(void) {}
uint32_t plat_cycles(void) { return (uint32_t)host_ns(); }
uint32_t plat_cycles_hz(void) { return 1000000000u; }
int plat_cycles_cpu(void) { return 0; }
uint32_t plat_ticks24(void) { return (uint32_t)(host_ns() * 24u / 1000u); }
uint32_t plat_irq_stack_used(void) { return 0; }
uint32_t plat_irq_stack_size(void) { return 0; }
uint32_t plat_cpu_peak_pct(void)
{
    uint32_t p = cpu_peak;
    cpu_peak = 0;
    return p;
}
int plat_stalls(uint32_t s[3]) { (void)s; return -1; }
void plat_stalls_enable(int on) { (void)on; }

/* -------------------------------------------------------------- app --- */
#include "../upstream/firmware/src/app/x0x.h"
#define ANN_NAME "X0X " X0X_VERSION
#include "ann_words.h"                                  /* the words file's link (tools/gen_words.py) */
#include "../upstream/firmware/src/announce.c"
static int ann_wire_send(const uint8_t *p,uint32_t n) {(void)p;(void)n;return 0;}
#include "../upstream/firmware/src/app/project.c"
#include "../upstream/firmware/src/app/ui.c"


static uint64_t host_frames, host_metrics[16];
static uint32_t host_ui_due;
/* Same persisted PAN5 calibration and defaults as app/panel.c. */
static struct { uint32_t magic;uint8_t btn[14],enc[7];int8_t dir[7]; } host_panel = {
 0x50414e35u,{2,3,4,5,6,7,8,9,10,11,12,13,0,1},{0,1,6,2,3,4,5},{1,1,1,1,1,1,1}
};
#pragma clang section bss = "" data = ""
void FEL(init)(void) {
    uint8_t saved[sizeof host_panel];
    if(plat_store_load(OBJ_PANEL,saved,sizeof saved)==sizeof saved) {
        uint32_t magic;memcpy(&magic,saved,4);int valid=magic==0x50414e35u;
        for(uint32_t i=0;i<14;i++)valid &= saved[4+i]<14;
        for(uint32_t i=0;i<7;i++)valid &= saved[18+i]<7 && (saved[25+i]==1 || saved[25+i]==255);
        if(valid)memcpy(&host_panel,saved,sizeof saved);
    }
    engine_init(proj.pat,&proj.arr.song,proj.arr.lane,&proj.sound);
    if(project_load()!=0)project_defaults();
    engine_apply_sound(&proj.sound);seq.bpm=(float)proj.set.bpm_x10/10.0f;
    seq.accent_q7=proj.set.accent_q7;project_apply_io();for(uint32_t k=0;k<SMP_USER_SLOTS;k++)smp_user_scan(k);engine_brk_loops();
    lcd_fill(0,0,240,240,C_BLACK);ui_init();
}
uint32_t FEL(ctl)(void) {return 256;}
uint32_t FEL(rate)(void) {return 44100;}
extern uint32_t fm1_x0x_native_part_mask(void);
void FEL(render)(int32_t *out,uint32_t n) {
    for(uint32_t i=0;i+256<=n;i+=256) {
        now_ms=(uint32_t)(host_frames*1000u/44100u);
        if(now_ms>=host_ui_due){host_ui_due=now_ms+16;ui_frame();}else ui_input_only();
        engine_render(out+i*2,256);engine_volume(out+i*2,256);engine_load(0,256);
        for(uint32_t j=0;j<512;j++){int32_t v=out[i*2+j];host_metrics[4]+=v!=0;out[i*2+j]=v>>7;}
        host_metrics[7]|=fm1_x0x_native_part_mask();
        host_frames+=256;host_metrics[0]+=256;
    }
}
void FEL(draw)(uint16_t *out){if(out)memcpy(out,fb,sizeof fb);}
/* physicalIDs match the manufacturer's panel; app roles follow upstream panel defaults. */

void FEL(physical_key)(uint32_t id,int down) {
 if(id<14u){uint32_t role=0;for(;role<14;role++)if(host_panel.btn[role]==id)break;if(role<14){if(down)held_btn|=1u<<role;else held_btn&=~(1u<<role);}}
 else if(id<41u){if(down)held_keys|=1u<<(id-14);else held_keys&=~(1u<<(id-14));}
}
void FEL(release_all)(void){held_keys=held_btn=0;}
void FEL(physical_encoder)(uint32_t id,int32_t n){if(id<7u)for(uint32_t r=0;r<7;r++)if(host_panel.enc[r]==id)enc_acc[r]+=n*host_panel.dir[r];}
void FEL(physical_leds)(float *out){
 for(uint32_t i=0;i<41;i++)out[i]=0;
 for(uint32_t b=0;b<14;b++)out[host_panel.btn[b]]=(lit_btn&(1u<<b))?0.086f:glow_on?0.001f:0;
 for(uint32_t k=0;k<27;k++)out[k+14]=(lit_keys&(1u<<k))?0.086f:(dim_keys&(1u<<k))?0.004f:0;
}
void FEL(volume)(uint32_t v){if(v>1023)v=1023;master=(v*v)>>8;}
void FEL(flash_load)(const uint8_t *p){memcpy(host_flash,p,HOST_FLASH_SIZE);}
void FEL(flash_copy)(uint8_t *p){memcpy(p,host_flash,HOST_FLASH_SIZE);}
uint32_t FEL(workload_metrics)(uint64_t *p,uint32_t c){uint32_t n=c<16?c:16;memcpy(p,host_metrics,n*sizeof *p);return n;}
