/* SPDX-License-Identifier: GPL-3.0-only
 * Standalone synthetic native-host Save/load/CRC test. Compile with
 * -DFM1_TEST_ADAPTER='"/absolute/built/native/hortator.c"' and generated includes. */
#define FEL_PREFIX qa_
#include FM1_TEST_ADAPTER
#include <assert.h>
#include <stdio.h>
static uint8_t image[1048576],before[1048576];
static void advance(unsigned frames){int32_t out[1024];while(frames>=512){qa_render(out,512);frames-=512;}}
static void tap(unsigned label){qa_physical_key(panel.btn[label],1);advance(2048);qa_physical_key(panel.btn[label],0);advance(2048);}
int main(int argc,char **argv) {
    assert(argc==3);
    if(!strcmp(argv[1],"read")){FILE *f=fopen(argv[2],"rb");assert(f&&fread(image,1,sizeof image,f)==sizeof image);fclose(f);}
    else memset(image,255,sizeof image);
    qa_flash_load(image);qa_volume(1023);qa_init();advance(132608);
    if(!strcmp(argv[1],"read")) {
        assert(lastp.set&&lastp.slot==1);assert(trk[0].p[P_LEVEL]==37);assert(!memcmp(chain.name,"POCKET QA",9));assert(theme_index(settings.palette)==1);
        puts("Hortator named slot B, last selection, settings and sound reopen");return 0;
    }
    tap(B_HOME);qa_physical_key(14,1);int32_t audio[1024];unsigned nz=0;
    for(int i=0;i<30;i++){qa_render(audio,512);for(int j=0;j<1024;j++)nz+=audio[j]!=0;}assert(nz);qa_release_all();advance(4096);
    trk[0].p[P_LEVEL]=37;memcpy(chain.name,"POCKET QA",10);settings.palette=THEME_TAG|1u;
    tap(B_SAVE);assert(cur_page()->fam==FAM_SAVE);
    qa_physical_encoder(panel.enc[EN_K1],1);advance(2048);assert(song.g[G_SLOT]==2);
    qa_physical_encoder(panel.enc[EN_K4],1);advance(2048);assert(ui.arm==G_SAVE);
    qa_physical_encoder(panel.enc[EN_K4],1);advance(2048);assert(lastp.set&&lastp.slot==1&&proj_ok(&proj_slot[1]));
    qa_flash_copy(image);FILE *f=fopen(argv[2],"wb");assert(f&&fwrite(image,1,sizeof image,f)==sizeof image);fclose(f);
    memcpy(before,image,sizeof image);int level=trk[0].p[P_LEVEL];
    for(unsigned copy=0;copy<2;copy++)hflash[st_sector(OBJ_PROJECT0+1,copy)]^=1;
    memcpy(before,hflash,sizeof before);memset(&proj_slot[1],0,sizeof proj_slot[1]);
    assert(!proj_load(1,1));assert(trk[0].p[P_LEVEL]==level);assert(!memcmp(before,hflash,sizeof before));
    puts("Hortator real SAVE knobs, audible HOME hit, CRC rejection without current-work mutation");return 0;
}
