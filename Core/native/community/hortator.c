/* SPDX-License-Identifier: GPL-3.0-only
 * PocketFM host for Hortator 0.25.0. HAL and boot order follow DEADACTIVE's
 * tests/sim_host.h and tests/sim_core.c; no browser demonstration song is installed.
 * The firmware's DSP, UI, presets, storage and project readers stay upstream. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "felucca_core.h"
static uint8_t host_sample_byte(uint32_t off);
#include "../upstream/tests/sim_host.h"
#undef __attribute__
static uint8_t host_sample_byte(uint32_t off) {
    if(off&0x80000000u){off&=0x7fffffffu;return off<sizeof hflash?hflash[off]:0;}
    return off<sizeof SMP_DATA?SMP_DATA[off]:0;
}
static uint32_t host_pos=HALF_FRAMES,host_master=716;
static int32_t host_knob=716*16;
static uint64_t host_next_frame,host_frames,host_nonzero;
static void host_frame(void) {
    song.batt_raw=600;
    host_knob+=((int32_t)host_master*16-host_knob)/8;
    uint32_t k=(uint32_t)(host_knob/16);song.master_q12=(k*k)>>8;
    felucca_dbg.ui_frames++;felucca_dbg.page=ui.page;felucca_dbg.home=ui.home;
    ui_input();ui_leds();ui_draw();
}
void FEL(init)(void) {
    persist_boot();settings_init();memset(&felucca_dbg,0,sizeof felucca_dbg);
    felucca_dbg.magic=DBG_MAGIC;felucca_dbg.boots=1;panel_init();drum_boot_init();audio_init();
    host_knob=(int32_t)host_master*16;host_frame();lcd_fill(0,0,240,240,C_BG);ui.force=1;
    host_next_frame=sim_samples+(FS*15u/1000u);
}
uint32_t FEL(ctl)(void){return CTL;}
uint32_t FEL(rate)(void){return FS;}
void FEL(render)(int32_t *out,uint32_t frames) {
    for(uint32_t k=0;k<frames;k++) {
        if(host_pos==HALF_FRAMES) {
            if(sim_samples>=host_next_frame){host_frame();host_next_frame+=FS*15u/1000u;}
            sim_half^=1u;fm1_alnk0_irq();sim_samples+=HALF_FRAMES;sim_ms_update();host_pos=0;
        }
        const int32_t *h=&abuf[sim_half*HALF_WORDS];
        /* Q24 I2S -> shared Q16 ABI; Native performs the final shift to Q15. */
        for(uint32_t c=0;c<2;c++){out[2u*k+c]=h[2u*host_pos+c]/128;host_nonzero+=out[2u*k+c]!=0;}
        host_pos++;
    }
    host_frames+=frames;
}
void FEL(draw)(uint16_t *out){for(uint32_t i=0;i<240u*240u;i++)out[i]=(uint16_t)((fb[i]>>8)|(fb[i]<<8));}
void FEL(physical_key)(uint32_t id,int down) {
    if(id<14u){uint32_t bit=1u<<id;if(down){fm1_in.pressed|=bit&~fm1_in.buttons;fm1_in.buttons|=bit;}else fm1_in.buttons&=~bit;}
    else if(id<41u){uint32_t bit=1u<<(id-14u);if(down){fm1_in.notes_pressed|=bit&~fm1_in.notes;fm1_in.notes|=bit;}else fm1_in.notes&=~bit;}
}
void FEL(release_all)(void){fm1_in.buttons=fm1_in.notes=fm1_in.pressed=fm1_in.notes_pressed=0;}
void FEL(physical_encoder)(uint32_t id,int32_t delta){if(id<7u)sim_enc_acc[id]+=delta;}
void FEL(physical_leds)(float *out) {
    for(uint32_t id=0;id<41u;id++) {
        out[id]=0;
        for(uint32_t c=0;c<FM1_NCOL;c++)for(uint32_t r=1;r<5u;r++)if(FM1_KEYMAP[r][c]==(int8_t)id)
            out[id]=(((led_dim_on?led_lay[c]|(led_lay[c]>>24):fm1_led[c])>>r)&1u)?95.f/1100.f:0;
    }
}
void FEL(volume)(uint32_t v){host_master=v>1023u?1023u:v;}
void FEL(flash_load)(const uint8_t *p){memcpy(hflash,p,sizeof hflash);}
void FEL(flash_copy)(uint8_t *p){memcpy(p,hflash,sizeof hflash);}
uint32_t FEL(workload_metrics)(uint64_t *p,uint32_t cap){uint64_t m[16]={0};m[0]=host_frames;m[4]=host_nonzero;uint32_t n=cap<16?cap:16;memcpy(p,m,n*sizeof *p);return n;}
