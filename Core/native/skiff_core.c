/* SPDX-License-Identifier: GPL-3.0-only
 * Native iOS adapter for Skiff v1.4's unchanged public browser/host application.
 * Skiff: illuminus5; based on Felucca by Leo Kuroshita / Hugelton Instruments.
 * The upstream audio ISR, UI, sequencer, project/pattern storage and DSP are used.
 * Source pin and generated resources: skiff.lock.json. No device SDK is linked. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <time.h>
#include <math.h>

/* Hostsim's unused desktop benchmark must never introduce iOS process APIs.
 * Its main is made static in the private build copy and optimized away. */
#define fork(...) (-1)
#define waitpid(...) (-1)
#pragma clang section bss="__DATA,__skfbss" data="__DATA,__skfdata"
static uint8_t skf_host_sample_byte(uint32_t offset);
#include "../upstream/web/emu/felucca_web.c"
#undef fork
#undef waitpid

/* Preserve 32-bit serialized sample offsets on a 64-bit host. The upper bit is
 * an internal virtual address tag; no host pointer is serialized or truncated. */
static uint8_t skf_host_sample_byte(uint32_t offset) {
    if (offset & 0x80000000u) {
        offset &= 0x7fffffffu;
        return offset < sizeof nor ? nor[offset] : 0;
    }
    return offset < sizeof SMP_DATA ? SMP_DATA[offset] : 0;
}
static uint64_t skf_metrics[16];
void skf_init(void) { web_boot(); }
uint32_t skf_ctl(void) { return 128; }
uint32_t skf_rate(void) { return FS; }
void skf_render(int32_t *out, uint32_t frames) {
    if (!out || frames > 1024u) return;
    web_render(frames);
    for (uint32_t i=0;i<frames;i++) {
        float l=out_l[i]*65536.0f,r=out_r[i]*65536.0f;
        out[2*i]=l>65534?65534:l<-65536?-65536:(int32_t)l;
        out[2*i+1]=r>65534?65534:r<-65536?-65536:(int32_t)r;
        skf_metrics[4]+=(out[2*i]!=0)+(out[2*i+1]!=0);
    }
    skf_metrics[0]+=frames;
    skf_metrics[1]=0;
    for(uint32_t t=0;t<NTRK;t++)for(uint32_t v=0;v<NVOICE;v++)skf_metrics[1]+=trk[t].v[v].active!=0;
    skf_metrics[2]=song.playing;
    skf_metrics[7]=web_flash_writes;
}
void skf_draw(uint16_t *out) { if(out)memcpy(out,web_fb,sizeof web_fb); }
void skf_physical_key(uint32_t id,int down) {
    if(id<14u) {
        uint32_t bit=1u<<id,old=fm1_in.buttons;
        if(down)fm1_in.buttons|=bit;else fm1_in.buttons&=~bit;
        web_pressed|=fm1_in.buttons&~old;web_released|=old&~fm1_in.buttons;
    } else if(id<41u) {
        uint32_t bit=1u<<(id-14),old=fm1_in.notes;
        if(down)fm1_in.notes|=bit;else fm1_in.notes&=~bit;
        web_key_mask=fm1_in.notes;web_notes_pressed|=fm1_in.notes&~old;
    }
}
void skf_release_all(void) {
    web_released|=fm1_in.buttons;fm1_in.notes=fm1_in.buttons=0;
    web_btn_labels=web_key_mask=web_pressed=web_notes_pressed=0;
}
void skf_physical_encoder(uint32_t id,int32_t delta) {if(id<7u)web_enc_steps[id]+=delta;}
void skf_volume(uint32_t value) {web_master(value);}
void skf_physical_leds(float *out) {
    if(!out)return;
    int anim=fm1_led_anim_on();
    for(uint32_t id=0;id<41;id++) {
        if(anim) {
            uint32_t value=fm1_anim_level(web_anim_frame(),id,web_anim_glow);
            out[id]=(value&127u)*(0.086f/64.0f)+((value&128u)?(web_dim_lo?0.0007f:0.0014f):0);
        } else {
            out[id]=led_on(fm1_led,id)?0.086f:led_on(fm1_led_mid,id)?0.008f:
                led_on(fm1_led_breath,id)?0.008f:led_on(fm1_led_dim,id)?(web_dim_lo?0.0007f:0.0014f):0;
        }
    }
}
void skf_flash_load(const uint8_t *bytes) {if(bytes)memcpy(nor,bytes,sizeof nor);}
void skf_flash_copy(uint8_t *bytes) {if(bytes)memcpy(bytes,nor,sizeof nor);}
uint32_t skf_workload_metrics(uint64_t *out,uint32_t capacity) {
    uint32_t n=capacity<16?capacity:16;if(out)memcpy(out,skf_metrics,n*sizeof *out);return n;
}
/* Synthetic-only test hooks, used by local native regressions; never owner data. */
void skf_test_heavy(void) {web_test_heavy();}
int skf_test_save_project(uint32_t slot) {return project_save(slot);}
void skf_test_load_project(uint32_t slot) {project_load(slot);}
uint32_t skf_test_project_copy(uint8_t *out,uint32_t capacity) {
    if(!out || capacity<sizeof(project_t))return sizeof(project_t);
    project_capture(&proj_scratch);memcpy(out,&proj_scratch,sizeof(project_t));return sizeof(project_t);
}
int skf_test_user_sample(uint32_t slot) {
    if(slot>=SMP_USER_SLOTS)return 0;
    smp_user_scan(slot);host_preset(&trk[0],ENGI_SAMPLE,0);trk[0].p[P_E0]=SMP_NSETS+slot;
    return usr_nz[slot];
}
