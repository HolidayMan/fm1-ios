/* SPDX-License-Identifier: GPL-3.0-only
 * Native fm1-base whole-application bridge, adapted from the GPL-3.0-only PocketFM FoMni bridge.
 * Upstream AMB-1/LOOM-8 and fm1-base files retain their MPL-2.0 notices. The exact upstream whole-app host, DSP, UI and physical
 * NOR storage are compiled; only platform I/O and the host boundary are adapted. */
#include <stdint.h>
#include <string.h>
#include "felucca_core_api.h"
#define PLAT_HOST 1
#define PLAT_WEB 1
static int32_t native_ring[4096*2];
static uint32_t native_w,native_r;
static uint64_t native_metrics[16];
static void web_audio(const int32_t *blk,uint32_t n) {
    for(uint32_t i=0;i<n;i++)for(uint32_t c=0;c<2;c++) {
        int32_t v=blk[i*2+c];
        native_ring[((native_w+i)%4096)*2+c]=v/128; /* upstream Q23 -> shared Q15<<1 */
        native_metrics[4]+=v!=0;
    }
    native_w+=n;native_metrics[0]+=n;
}
#include "../upstream/base/host/plat_host.c"
#undef __attribute__
static void web_said(const uint8_t *p,uint32_t n){(void)p;(void)n;}
static const uint8_t native_btn[14]={12,13,0,1,2,3,4,5,6,7,8,9,10,11};
static const uint8_t native_enc[7]={EN_SELECT,EN_ALGO,EN_K1,EN_K2,EN_K3,EN_K4,EN_PRESET};
void FEL(init)(void){boot();}
uint32_t FEL(ctl)(void){return 256;}
uint32_t FEL(rate)(void){return 44100;}
void FEL(render)(int32_t *out,uint32_t frames){
    for(uint32_t i=0;i<frames;i++) {
        while(native_r==native_w)run_ms(1);
        out[i*2]=native_ring[(native_r%4096)*2];out[i*2+1]=native_ring[(native_r%4096)*2+1];native_r++;
    }
}
void FEL(draw)(uint16_t *out){memcpy(out,fb,sizeof fb);}
void FEL(physical_key)(uint32_t id,int down){
    uint32_t *bits,bit;
    if(id<14){bits=&held_btn;bit=1u<<native_btn[id];}else if(id<41){bits=&held_keys;bit=1u<<(id-14);}else return;
    if(down)*bits|=bit;else *bits&=~bit;
}
void FEL(release_all)(void){held_btn=held_keys=0;}
void FEL(physical_encoder)(uint32_t id,int32_t n){if(id<7)enc_acc[native_enc[id]]+=n;}
void FEL(physical_leds)(float *out){
    for(uint32_t id=0;id<41;id++)out[id]=id<14?((lit_btn&(1u<<native_btn[id]))?95.f/1100.f:glow_on?4.f/1100.f:0):((lit_keys&(1u<<(id-14)))?95.f/1100.f:0);
}
void FEL(volume)(uint32_t n){master=(n>1023?1023:n)*4;}
void FEL(flash_load)(const uint8_t *p){memcpy(host_flash,p,sizeof host_flash);}
void FEL(flash_copy)(uint8_t *p){memcpy(p,host_flash,sizeof host_flash);}
uint32_t FEL(workload_metrics)(uint64_t *p,uint32_t cap){native_metrics[12]=store_writes;uint32_t n=cap<16?cap:16;memcpy(p,native_metrics,n*sizeof *p);return n;}
