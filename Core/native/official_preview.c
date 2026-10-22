/* Native host of the exact public V14 browser sources, not the opaque device SDK. */
#include "official_preview_host.h"
#undef malloc
#undef calloc
#undef free
#include <string.h>
#include <limits.h>
struct allocation { struct allocation *next; void *memory; };
static struct allocation *allocations;
static uint64_t allocation_failures, blocks_rendered;
void *ofp_alloc(size_t size) {
    void *memory=malloc(size); if(!memory){++allocation_failures;return NULL;}
    struct allocation *node=malloc(sizeof *node);
    if(!node){free(memory);++allocation_failures;return NULL;}
    node->memory=memory;node->next=allocations;allocations=node;return memory;
}
void *ofp_calloc(size_t n,size_t size) {
    if(size && n>SIZE_MAX/size){++allocation_failures;return NULL;}
    void *p=ofp_alloc(n*size);if(p)memset(p,0,n*size);return p;
}
void ofp_free(void *p) {
    if(!p)return;
    struct allocation **link=&allocations;
    while(*link){if((*link)->memory==p){struct allocation *node=*link;*link=node->next;free(p);free(node);return;}link=&(*link)->next;}
    /* Every upstream allocation must belong to this bound instance. */
    abort();
}
void ofp_destroy(void) {
    while(allocations){struct allocation *node=allocations;allocations=node->next;free(node->memory);free(node);}
}
extern void sim_boot(unsigned);
extern void sim_control(unsigned,unsigned,int);
extern void sim_release(void);
extern const float *sim_render(void);
extern const uint16_t *sim_pixels(void);
extern const uint8_t *sim_state(void);
extern uint8_t *sim_flash(void);
extern unsigned sim_block_frames(void);
#define FLASH_BYTES 536576U
uint32_t ofp_ctl(void){return sim_block_frames();}
uint32_t ofp_rate(void){return 44100;}
void ofp_init(void){
    uint8_t *f=sim_flash();unsigned blank=1;
    for(unsigned i=0;i<FLASH_BYTES;++i)if(f[i]!=255){blank=0;break;}
    sim_boot(blank); /* upstream preview's original synthesized sample defaults */
}
void ofp_render(int32_t *out,uint32_t frames){
    if(!out || frames!=ofp_ctl())return;
    const float *p=sim_render();
    for(unsigned i=0;i<frames*2;++i){float x=p[i]*65536.0f;out[i]=x>65534?65534:x<-65536?-65536:(int32_t)x;}
    ++blocks_rendered;
}
void ofp_draw(uint16_t *out){
    if(!out)return;const uint16_t *p=sim_pixels();
    for(unsigned i=0;i<240*240;++i)out[i]=(uint16_t)((p[i]<<8)|(p[i]>>8));
}
void ofp_physical_key(uint32_t id,int32_t down){if(id<14)sim_control(0,id,!!down);else if(id<41)sim_control(1,id-14,!!down);}
void ofp_release_all(void){sim_release();}
void ofp_physical_encoder(uint32_t id,int32_t delta){if(id<7)sim_control(2,id,delta<-127?-127:delta>127?127:delta);}
void ofp_physical_leds(float *out){if(out){const uint8_t *s=sim_state()+168;for(unsigned i=0;i<41;++i)out[i]=s[i]?1.0f:0.0f;}}
void ofp_volume(uint32_t value){sim_control(3,0,value>1023?1023:(int)value);}
void ofp_flash_load(const uint8_t *data){if(data)memcpy(sim_flash(),data,FLASH_BYTES);}
void ofp_flash_copy(uint8_t *data){if(data)memcpy(data,sim_flash(),FLASH_BYTES);}
uint32_t ofp_workload_metrics(uint64_t *out,uint32_t cap){
    if(out){for(unsigned i=0;i<cap&&i<16;++i)out[i]=0;if(cap>0)out[0]=blocks_rendered;if(cap>12)out[12]=allocation_failures;}return cap<16?cap:16;
}

/* Public browser build has no optional hardware MIDI panel state. V14
 * declares this hook weak; provide its absent-hook no-op for native linkers. */
void groove_midi_panel_reset(void) {}
