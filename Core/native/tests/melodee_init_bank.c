/* SPDX-License-Identifier: GPL-3.0-only
 * Compile beside a build's native/melodee_core.c with its matching resources.
 * old-probe write fixture; INIT-probe read fixture. New synthetic user data only.
 * No proprietary factory program is used by the fixture generator. */
#include "melodee_core.c"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static void tick(unsigned frames) { int32_t pcm[2*CTL];for(unsigned i=0;i<frames;i+=CTL)mel_render(pcm,CTL); }
static uint64_t note(unsigned engine) {
    mel_release_all();mel_set_engine(0,engine);mel_apply_preset(0,0);tick(FS/2);
    mel_physical_key(21,1);int32_t pcm[2*CTL];uint64_t n=0;
    for(unsigned i=0;i<FS;i+=CTL){mel_render(pcm,CTL);for(unsigned j=0;j<2*CTL;j++)n+=pcm[j]!=0;}
    mel_physical_key(21,0);tick(FS/2);return n;
}
int main(int argc,char **argv) {
    assert(argc==3);int writing=!strcmp(argv[1],"write");assert(writing||!strcmp(argv[1],"read"));
    uint8_t *flash=malloc(HOST_FLASH_SIZE);assert(flash);memset(host_flash,255,HOST_FLASH_SIZE);
    FILE *f=fopen(argv[2],writing?"wb":"rb");assert(f);
    cz_patch_t want_cz[NTRK];p5_patch_t want_p5[NTRK];
    if(!writing){assert(fread(host_flash,1,HOST_FLASH_SIZE,f)==HOST_FLASH_SIZE);assert(fread(want_cz,1,sizeof want_cz,f)==sizeof want_cz);assert(fread(want_p5,1,sizeof want_p5,f)==sizeof want_p5);assert(fgetc(f)==EOF);}
    mel_init();tick(FS);
#ifndef OLD_SOURCE
    _Static_assert(CZ_FACTORY_N==0 && P5_FACTORY_N==0,"No upstream factory programs");
    assert(mel_npresets(ENGI_CZ)==1 && mel_npresets(ENGI_PROPHET)==1);
    assert(!strcmp(mel_preset_name(ENGI_CZ,0),"POCKET CZ INIT"));
    assert(!strcmp(mel_preset_name(ENGI_PROPHET,0),"POCKET P5 INIT"));
    for(unsigned k=1;k<=264;k++){assert(!*mel_preset_name(ENGI_CZ,k));assert(!*mel_preset_name(ENGI_PROPHET,k));}
    for(unsigned k=0;k<CZ_BANK_N;k++)if(writing)assert(cz_bank_load(k)->used==0);
#endif
    uint64_t cz_audio=0,p5_audio=0;
    if(writing){
        cz_audio=note(ENGI_CZ);p5_audio=note(ENGI_PROPHET);assert(cz_audio>100 && p5_audio>100);
        mel_set_engine(0,ENGI_CZ);mel_apply_preset(0,0);tick(FS/2);
        mel_set_engine(1,ENGI_PROPHET);mel_apply_preset(1,0);tick(FS/2);
        /* Personal edits to the public technical INIT encodings, never ROM sounds. */
        cz_patch[0].raw[23]=0xD7;memcpy(cz_patch[0].raw+128,"USER TEST CZ    ",16);
        p5_patch_t *p=&p5_patch[1];p->raw[P5_CUTOFF]=77;p->raw[P5_LEVEL_A]=95;
        memset(p->raw+P5_NAME,' ',P5_NAME_LEN);memcpy(p->raw+P5_NAME,"USER TEST P5",12);
        assert(cz_patch_valid(cz_patch[0].raw));assert(p5_patch_valid(p));
        assert(!native_put(ENGI_CZ,7,cz_patch[0].raw));assert(!native_put(ENGI_PROPHET,8,(uint8_t*)p));
        assert(!project_save_as(3,"USER INIT TEST"));
        memcpy(want_cz,cz_patch,sizeof want_cz);memcpy(want_p5,p5_patch,sizeof want_p5);
        assert(fwrite(host_flash,1,HOST_FLASH_SIZE,f)==HOST_FLASH_SIZE);
        assert(fwrite(want_cz,1,sizeof want_cz,f)==sizeof want_cz);assert(fwrite(want_p5,1,sizeof want_p5,f)==sizeof want_p5);
    }else{
        project_load(3);
        assert(!memcmp(want_cz,cz_patch,sizeof want_cz));assert(!memcmp(want_p5,p5_patch,sizeof want_p5));
        assert(native_used(ENGI_CZ,7) && native_used(ENGI_PROPHET,8));
        assert(!memcmp(native_raw(ENGI_CZ,7),want_cz[0].raw,CZ_BYTES));
        assert(!memcmp(native_raw(ENGI_PROPHET,8),&want_p5[1],sizeof(p5_patch_t)));
    }
    printf("{\"derivedINIT\":%s,\"mode\":\"%s\",\"czNonzero\":%llu,\"p5Nonzero\":%llu,\"userProjectAndNativeBanksPreserved\":true}\n",
#ifdef OLD_SOURCE
        "false",
#else
        "true",
#endif
        writing?"write":"read",cz_audio,p5_audio);
    fclose(f);free(flash);return 0;
}
