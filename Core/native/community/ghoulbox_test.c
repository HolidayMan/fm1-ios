/* SPDX-License-Identifier: GPL-3.0-only
 * Synthetic native host boot, keyboard, private autosave and NOR CRC test. */
#define FEL_PREFIX qa_
#include FM1_TEST_ADAPTER
#include <assert.h>
#include <stdio.h>
static uint8_t image[1048576],before[1048576];
static void advance(unsigned n){int32_t out[1024];while(n>=512){qa_render(out,512);n-=512;}}
int main(int argc,char **argv) {
    assert(argc==3);
    if(!strcmp(argv[1],"read")){FILE *f=fopen(argv[2],"rb");assert(f&&fread(image,1,sizeof image,f)==sizeof image);fclose(f);}
    else memset(image,255,sizeof image);
    qa_flash_load(image);qa_volume(1023);qa_init();advance(132608);
    if(!strcmp(argv[1],"read")){assert(trk[0].p[P_LEVEL]==37&&settings.palette==1);puts("ghoulbox latest private autosave reopens");return 0;}
    qa_physical_key(21,1);int32_t audio[1024];unsigned nz=0;
    for(int i=0;i<40;i++){qa_render(audio,512);for(int j=0;j<1024;j++)nz+=audio[j]!=0;}assert(nz);qa_release_all();
    settings.palette=1;settings_save();qa_flash_copy(before);trk[0].p[P_LEVEL]=37;qa_flash_copy(image);
    unsigned sectors[2]={st_sector(OBJ_AUTOSAVE,0),st_sector(OBJ_AUTOSAVE,1)};
    for(unsigned i=0;i<sizeof image;i++)if(image[i]!=before[i])assert((i>=sectors[0]&&i<sectors[0]+4096)||(i>=sectors[1]&&i<sectors[1]+4096));
    st_hdr_t header;int copy=st_current(OBJ_AUTOSAVE,&header);assert(copy>=0&&st_body(OBJ_AUTOSAVE,(unsigned)copy,&header)==0);
    FILE *f=fopen(argv[2],"wb");assert(f&&fwrite(image,1,sizeof image,f)==sizeof image);fclose(f);
    uint32_t sig=autosave_sig();for(unsigned c=0;c<2;c++)nor[st_sector(OBJ_AUTOSAVE,c)]^=1;
    memcpy(before,nor,sizeof before);assert(st_load(OBJ_AUTOSAVE,&proj_wire,sizeof proj_wire)<0);
    assert(autosave_sig()==sig&&!memcmp(before,nor,sizeof before));
    puts("ghoulbox keyboard sounds; only private autosave sectors change; corrupt NOR rejected without mutation");return 0;
}
