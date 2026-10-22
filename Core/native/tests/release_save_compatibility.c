/* SPDX-License-Identifier: GPL-3.0-only
 * Synthetic cross-release fixtures; never pass private user data.
 * Build twice with -DKIND=5/6/7 and the old/new native archive respectively.
 * old-probe write fixture.bin; new-probe read fixture.bin.
 * Checks actual logical saved content, not just flash length or restore success. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if KIND == 5
#define PREFIX mel_
#define FLASH_BYTES 1048576
extern int32_t mel_object_get(uint32_t,uint8_t*,uint32_t);
extern uint32_t mel_object_put(uint32_t,const uint8_t*,uint32_t);
#define LOGICAL_CAPACITY 65536
extern uint32_t mel_pcount(void);
extern uint32_t mel_ntracks(void);
extern int32_t mel_param_get(uint32_t,uint32_t);
static unsigned capture(uint8_t *out) { unsigned n=0;for(unsigned t=0;t<mel_ntracks();t++)for(unsigned p=0;p<mel_pcount();p++){int32_t v=mel_param_get(t,p);memcpy(out+n,&v,4);n+=4;}return n; }
#elif KIND == 6
#define PREFIX ofp_
#define FLASH_BYTES 536576
#define LOGICAL_CAPACITY 4064
extern int ofp_up_groove_project_capture(void*);
extern int ofp_up_groove_project_save_slot(unsigned);
extern int ofp_up_groove_project_load_slot(unsigned);
extern void ofp_up_groove_project_rename(unsigned,char);
static unsigned capture(uint8_t *out) { assert(!ofp_up_groove_project_capture(out));return LOGICAL_CAPACITY; }
#elif KIND == 7
#define PREFIX skf_
#define FLASH_BYTES 1048576
#define LOGICAL_CAPACITY 65536
extern void skf_test_heavy(void);
extern int skf_test_save_project(uint32_t);
extern void skf_test_load_project(uint32_t);
extern uint32_t skf_test_project_copy(uint8_t*,uint32_t);
static unsigned capture(uint8_t *out) { unsigned n=skf_test_project_copy(out,LOGICAL_CAPACITY);assert(n&&n<=LOGICAL_CAPACITY);return n; }
#else
#error Choose a supported native KIND.
#endif
#define JOIN_(a,b) a##b
#define JOIN(a,b) JOIN_(a,b)
#define API(x) JOIN(PREFIX,x)
extern uint64_t API(state_size)(void);
extern int API(state_init)(void*);
extern void API(bind)(void*);
extern void API(init)(void);
extern void API(render)(int32_t*,uint32_t);
extern uint32_t API(ctl)(void);
extern void API(flash_load)(const uint8_t*);
extern void API(flash_copy)(uint8_t*);
extern void API(physical_encoder)(uint32_t,int32_t);
static void tick(void){int32_t out[2048];unsigned n=API(ctl)();assert(n<=1024);for(unsigned i=0;i<44100/n;i++)API(render)(out,n);}
int main(int argc,char **argv){
 assert(argc==3);int writing=!strcmp(argv[1],"write");assert(writing||!strcmp(argv[1],"read"));
 uint8_t *flash=malloc(FLASH_BYTES),*logical=malloc(LOGICAL_CAPACITY),*want=malloc(LOGICAL_CAPACITY);assert(flash&&logical&&want);memset(flash,255,FLASH_BYTES);
 FILE *file=fopen(argv[2],writing?"wb":"rb");assert(file);
 unsigned expected=0;if(!writing){assert(fread(flash,1,FLASH_BYTES,file)==FLASH_BYTES);assert(fread(&expected,4,1,file)==1&&expected<=LOGICAL_CAPACITY);assert(fread(want,1,expected,file)==expected);assert(fgetc(file)==EOF);}
 void *state;assert(!posix_memalign(&state,64,API(state_size)()));assert(API(state_init)(state));API(bind)(state);API(flash_load)(flash);API(init)();tick();
 if(writing){
#if KIND == 5
  API(physical_encoder)(6,1);for(unsigned i=0;i<30;i++)tick();
#elif KIND == 6
  ofp_up_groove_project_rename(0,'Q');ofp_up_groove_project_rename(1,'A');assert(!ofp_up_groove_project_save_slot(3));assert(!ofp_up_groove_project_load_slot(3));
#elif KIND == 7
  skf_test_heavy();assert(!skf_test_save_project(3));skf_test_load_project(3);
#endif
 }else{
#if KIND == 6
  assert(!ofp_up_groove_project_load_slot(3));
#elif KIND == 7
  skf_test_load_project(3);
#endif
 }
 unsigned length=capture(logical);
 if(writing){API(flash_copy)(flash);assert(fwrite(flash,1,FLASH_BYTES,file)==FLASH_BYTES);assert(fwrite(&length,4,1,file)==1);assert(fwrite(logical,1,length,file)==length);}
 else{assert(length==expected);assert(!memcmp(logical,want,length));printf("{\"nativeKind\":%d,\"oldLogicalSavePreserved\":true,\"logicalBytes\":%u}\n",KIND,length);}
 fclose(file);free(state);free(flash);free(logical);free(want);return 0;
}
