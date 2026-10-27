# SPDX-License-Identifier: MPL-2.0
"""Exact host I/O substitutions; source DSP/UI/timing and hardware NOR commit code remain upstream."""
from pathlib import Path
import re

NOR='''static uint32_t store_writes,store_tries;
static int st_read(uint32_t off,void *dst,uint32_t n){if(off>0x100000u||n>0x100000u-off)return -1;memcpy(dst,host_flash+off,n);return 0;}
static int st_erase(uint32_t off){if((off&4095u)||off>0xff000u)return -1;memset(host_flash+off,255,4096);return 0;}
static int st_prog(uint32_t off,const void *src,uint32_t n){if(off>0x100000u||n>0x100000u-off)return -1;for(uint32_t i=0;i<n;i++)host_flash[off+i]&=((const uint8_t *)src)[i];return 0;}
#include "storage.c"
int plat_store_load(uint32_t obj,void *dst,uint32_t n){return st_load(obj,dst,n);}
int plat_store_save(uint32_t obj,const void *src,uint32_t n){int rc=st_save(obj,src,n);if(!rc)store_writes++;return rc;}
'''

def adapt(upstream):
    # App-specific host.c files are CLI test/profiling tools, not instrument
    # code. The normal app uses identical DSP and its serial CPU2 fallback.
    app=upstream/'app/app.c';text=app.read_text()
    if text.count('#include "host.c"')!=1:raise SystemExit('fm1-base app host hook changed')
    app.write_text(text.replace('#include "host.c"','/* PocketFM: omit CLI-only test/profiling commands. */'))
    header=upstream/'app/app.h'
    header.write_text(re.sub(r'^#define APP_HOST_[A-Z0-9_]+.*$', '',header.read_text(),flags=re.M))
    p=upstream/'base/host/plat_host.c';s=p.read_text()
    s=s.replace('#include "plat.h"','static uint8_t host_flash[0x100000u];\n#include "plat.h"',1)
    start=s.index('/* flash: one buffer per object, kept across a simulated reboot */');end=s.index('static uint32_t cpu_pct;',start)
    block=NOR
    if 'int plat_store_head(' in s:
        block+='int plat_store_head(uint32_t obj,void *dst,uint32_t n){return st_load_head(obj,dst,n);}\nint plat_store_size(uint32_t obj){return st_size(obj);}\nconst uint8_t *plat_chip_uid(void){static const uint8_t uid[16]={0x46,0x4d,0x31};return uid;}\n'
    s=s[:start]+block+s[end:]
    # The source's separate simulated data array must alias the same saved NOR.
    s,n=re.subn(r'static uint8_t data_area\[[^;]+;\nstatic uint8_t data_ready;\nstatic void data_init\(void\)\n\{.*?\n\}', '#define data_area (host_flash + '+('DATA_BASE' if '#define DATA_BASE' in s else 'PLAT_DATA_LO')+')\nstatic void data_init(void) {}',s,flags=re.S)
    if n!=1:raise SystemExit('fm1-base data-area anchor changed')
    # File/PNG/WAV helpers are CLI facilities, never part of the signed library.
    start=s.index('/* ---------------------------------------------------------- outputs --- */');end=s.index('static double audio_due_ms',start)
    s=s[:start]+'static float peak_out;\n'+s[end:]
    s,n=re.subn(r'\n\s*if \(wav\) \{\n\s*fwrite\(s, 2, 2, wav\);\n\s*wav_frames\+\+;\n\s*\}', '',s)
    if n!=1:raise SystemExit('fm1-base WAV hook anchor changed')
    s,n=re.subn(r'\n    if \(midi_log\)\n        fprintf\(midi_log,.*?;\n','\n',s,flags=re.S)
    if n!=1:raise SystemExit('fm1-base MIDI-log anchor changed')
    p.write_text(s)
