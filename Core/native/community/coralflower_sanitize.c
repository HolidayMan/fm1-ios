/* SPDX-License-Identifier: GPL-3.0-only
 * Standalone memory/undefined-behavior probe; synthetic state only. */
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
extern uint64_t cfl_state_size(void);
extern int cfl_state_init(void *);
extern void cfl_bind(void *),cfl_init(void);
extern void cfl_render(int32_t *,uint32_t),cfl_draw(uint16_t *);
extern void cfl_physical_key(uint32_t,int),cfl_physical_encoder(uint32_t,int32_t);
extern void cfl_release_all(void),cfl_flash_load(const uint8_t *),cfl_flash_copy(uint8_t *);
extern void cfl_volume(uint32_t);
static void save_receipt(const char *name,const uint8_t *bytes)
{
    FILE *f=fopen(name,"wb");assert(f);
    assert(fwrite(bytes,1,1u<<20,f)==(1u<<20));assert(!fclose(f));
}
int main(void)
{
    void *a=NULL,*b=NULL;
    assert(posix_memalign(&a,16,cfl_state_size())==0);
    assert(posix_memalign(&b,16,cfl_state_size())==0);
    uint8_t *flash=malloc(1u<<20),*copy=malloc(1u<<20);
    uint16_t *lcd=malloc(240*240*sizeof *lcd);
    int32_t *out=malloc(1024*2*sizeof *out);
    assert(flash&&copy&&lcd&&out);
    memset(flash,255,1u<<20);
    assert(cfl_state_init(a));cfl_bind(a);cfl_flash_load(flash);cfl_init();
    assert(cfl_state_init(b));cfl_bind(b);cfl_flash_load(flash);cfl_init();
    long peak=0;
    for(unsigned i=0;i<900;i++) {
        cfl_bind(i&1?a:b);
        if(i%30==0)cfl_physical_key(14+i%27,1);
        if(i%30==20)cfl_release_all();
        if(i%80==0)cfl_physical_encoder(6,1);
        if(i%103==0)cfl_physical_key(1,1);
        if(i%103==2)cfl_physical_key(1,0);
        cfl_physical_key(UINT32_MAX,1);cfl_physical_encoder(UINT32_MAX,1);
        cfl_volume(i%100==0?UINT32_MAX:716);
        unsigned frames=i%3==0?1:i%3==1?127:1024;
        cfl_render(out,frames);
        for(unsigned k=0;k<2*frames;k++)if(labs(out[k])>peak)peak=labs(out[k]);
        cfl_draw(lcd);cfl_flash_copy(copy);
    }
    assert(peak>100);
    cfl_bind(a);cfl_release_all();cfl_render(out,1024);cfl_flash_copy(flash);
    save_receipt("before.flash",flash);
    /* The boundary restores the exact NOR bytes. Upstream cf_settings_read may
     * subsequently compact its settings log at power-on (st_tidy); semantic
     * persisted settings are covered by coralflower_test.py. */
    assert(cfl_state_init(b));cfl_bind(b);cfl_flash_load(flash);cfl_flash_copy(copy);
    assert(!memcmp(flash,copy,1u<<20));
    cfl_init();cfl_flash_copy(copy);save_receipt("after.flash",copy);
    cfl_render(out,1024);
    free(a);free(b);free(flash);free(copy);free(lcd);free(out);
    printf("CoralFlower sanitizer probe passed; peak %ld\n",peak);
    return 0;
}
