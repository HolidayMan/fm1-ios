/* SPDX-License-Identifier: GPL-3.0-only
 * Synthetic host regression for the pinned native Skiff adapter. Never owner data.
 * clang -O2 skiff_smoke.c libfm1_native_skiff.a -o smoke && ./smoke */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
extern uint64_t skf_state_size(void);
extern int skf_state_init(void*);
extern void skf_bind(void*);
extern void skf_init(void);
extern void skf_render(int32_t*,uint32_t);
extern void skf_draw(uint16_t*);
extern void skf_physical_key(uint32_t,int);
extern void skf_release_all(void);
extern void skf_flash_load(const uint8_t*);
extern void skf_flash_copy(uint8_t*);
extern uint32_t skf_workload_metrics(uint64_t*,uint32_t);
extern void skf_test_heavy(void);
extern int skf_test_save_project(uint32_t);
extern void skf_test_load_project(uint32_t);
extern uint32_t skf_test_project_copy(uint8_t*,uint32_t);
extern int skf_test_user_sample(uint32_t);
#define FLASH 1048576u
static int32_t pcm[256];
static void*make(const uint8_t *flash){void*p;assert(!posix_memalign(&p,16,skf_state_size()));assert(skf_state_init(p));skf_bind(p);skf_flash_load(flash);skf_init();return p;}
static void run(void*p,unsigned frames){skf_bind(p);for(unsigned i=0;i<frames;i+=128)skf_render(pcm,128);}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static void sample(uint8_t*f,unsigned slot){unsigned at=0xa0000+slot*0x14000;uint8_t*h=f+at;memset(h,0,512);uint32_t v=0x504d5346;memcpy(h,&v,4);h[4]=1;h[6]=1;memcpy(h+8,"TESTKIT",7);v=4096;memcpy(h+16,&v,4);uint8_t*z=h+32;v=8192;memcpy(z+4,&v,4);v=8191;memcpy(z+12,&v,4);v=65536;memcpy(z+16,&v,4);int16_t pitch=60*16;memcpy(z+20,&pitch,2);z[26]=127;z[27]=1;for(unsigned i=0;i<4096;i++)h[512+i]=i%64<32?0x77:0xff;}
int main(void){
 uint8_t*blank=malloc(FLASH),*saved=malloc(FLASH),*got=malloc(FLASH);assert(blank&&saved&&got);memset(blank,255,FLASH);
 void*a=make(blank);run(a,22050);skf_physical_key(21,1);uint64_t nonzero=0;for(unsigned i=0;i<44100;i+=128){skf_render(pcm,128);for(unsigned j=0;j<256;j++)nonzero+=pcm[j]!=0;}assert(nonzero);skf_release_all();
 uint16_t pixels[57600];skf_draw(pixels);unsigned nonzero_pixels=0;for(unsigned i=0;i<57600;i++)nonzero_pixels+=pixels[i]!=0;assert(nonzero_pixels);
 // Preserve complete physical NOR, including firmware and sample areas outside save objects.
 skf_flash_copy(saved);void*b=make(saved);skf_flash_copy(got);assert(!memcmp(saved,got,FLASH));
 // Actual original project and pattern persistence, independently reopened.
 skf_bind(a);skf_test_heavy();assert(skf_test_save_project(0)==0);
 unsigned project_size=skf_test_project_copy(NULL,0);uint8_t*project=malloc(project_size),*reopened=malloc(project_size);assert(project&&reopened);assert(skf_test_project_copy(project,project_size)==project_size);skf_flash_copy(saved);
 void*c=make(saved);skf_test_load_project(0);assert(skf_test_project_copy(reopened,project_size)==project_size);assert(!memcmp(project,reopened,project_size));
 // Writes in one bound instance must not mutate a neighbor's backing flash.
 skf_bind(b);skf_flash_copy(got);assert(memcmp(saved,got,FLASH));skf_bind(c);skf_flash_copy(got);assert(!memcmp(saved,got,FLASH));
 free(a);free(b);free(c);free(project);free(reopened);
 // State/DSP/RNG isolation across alternating calls and identical source inputs.
 a=make(blank);b=make(blank);run(a,22050);run(b,22050);skf_bind(a);skf_test_heavy();skf_physical_key(12,1);skf_bind(b);skf_test_heavy();skf_physical_key(12,1);
 int32_t other[256];double start=now();uint64_t heavy_nonzero=0;for(unsigned block=0;block<3446;block++){skf_bind(a);skf_render(pcm,128);skf_bind(b);skf_render(other,128);assert(!memcmp(pcm,other,sizeof pcm));if(block==32){skf_bind(a);skf_physical_key(12,0);skf_bind(b);skf_physical_key(12,0);}for(unsigned j=0;j<256;j++)heavy_nonzero+=pcm[j]!=0;}double elapsed=now()-start;assert(heavy_nonzero);free(a);free(b);
 // All three saved user sample slots must sound with 64-bit-safe virtual offsets.
 uint64_t user_nonzero[3]={0};for(unsigned slot=0;slot<3;slot++){memset(blank,255,FLASH);sample(blank,slot);a=make(blank);run(a,22050);skf_bind(a);assert(skf_test_user_sample(slot)==1);run(a,4096);skf_physical_key(21,1);for(unsigned i=0;i<22050;i+=128){skf_render(pcm,128);for(unsigned j=0;j<256;j++)user_nonzero[slot]+=pcm[j]!=0;}assert(user_nonzero[slot]);skf_flash_copy(got);assert(!memcmp(got+0xa0000,blank+0xa0000,0x3c000));free(a);}
 printf("{\"source\":\"Skiff1.4\",\"stateBytes\":%llu,\"flashBytes\":%u,\"nonzeroSamples\":%llu,\"nonzeroPixels\":%u,\"projectReopened\":true,\"physicalFlashRoundTrip\":true,\"instanceIsolation\":true,\"userSampleSlots\":[%llu,%llu,%llu],\"heavyRenderedSecondsPerInstance\":%.9f,\"twoInstanceWallSeconds\":%.9f,\"heavyNonzeroSamples\":%llu}\n",skf_state_size(),FLASH,nonzero,nonzero_pixels,user_nonzero[0],user_nonzero[1],user_nonzero[2],3446*128/44100.0,elapsed,heavy_nonzero);
 free(blank);free(saved);free(got);return 0;
}
