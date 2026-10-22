#!/usr/bin/env python3
"""Compile exact additional firmware sources; never fetch or replace inputs during builds."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from build_family import TRIPLES, validate
from target_config import Toolchain
HERE=Path(__file__).resolve().parent

def run(*args):subprocess.run([str(x) for x in args],check=True)

def verify_expansion(source,descriptor):
    validate(source,descriptor)
    run('git','-C',source,'diff','--exit-code','HEAD')
    actual={str(f.relative_to(source)):hashlib.sha256(f.read_bytes()).hexdigest()
            for directory in ['firmware','host','tools','assets','web/words']
            for f in sorted((source/directory).rglob('*')) if f.is_file()}
    if actual!=descriptor['inputs']:raise SystemExit('Exact source/resource input set differs: '+descriptor['id'])
    for name,want in descriptor['notices_sha256'].items():
        if hashlib.sha256((source/name).read_bytes()).hexdigest()!=want:raise SystemExit('Changed notice: '+name)

def namespace_ir(text,prefix):
    """Namespace every defined public symbol across the linked firmware translation units.

    External libc declarations stay external; internal/private globals already have
    LLVM-local identity. Rewrite references together, including constant pointer tables.
    """
    names=set()
    for line in text.splitlines():
        if line.startswith('define ') and not re.match(r'define (?:internal|private) ',line):
            m=re.search(r'@([A-Za-z_.$][\w.$]*)\(',line)
            if m:names.add(m[1])
        m=re.match(r'@([A-Za-z_.$][\w.$]*) = (?!internal\b|private\b|external\b)',line)
        if m:names.add(m[1])
    names={name for name in names if not name.startswith(prefix) and not name.startswith('llvm.')}
    return re.sub(r'@([A-Za-z_.$][\w.$]*)',lambda m:'@'+prefix+m[1] if m[1] in names else m[0],text)

NOR='''/* Physical NOR hooks: unchanged upstream storage.c owns map, CRC and A/B saves. */
#define HOST_FLASH_SIZE 0x100000u
static uint8_t host_flash[HOST_FLASH_SIZE];
static uint32_t store_writes;
static int st_read(uint32_t off,void *dst,uint32_t n){if(off>HOST_FLASH_SIZE||n>HOST_FLASH_SIZE-off)return -1;memcpy(dst,host_flash+off,n);return 0;}
static int st_erase(uint32_t off){if((off&4095u)||off>HOST_FLASH_SIZE-4096u)return -8;memset(host_flash+off,255,4096);return 0;}
static int st_prog(uint32_t off,const void *src,uint32_t n){if(off>HOST_FLASH_SIZE||n>HOST_FLASH_SIZE-off)return -8;const uint8_t *p=src;for(uint32_t i=0;i<n;i++)host_flash[off+i]&=p[i];return 0;}
#include "../firmware/src/storage.c"
int plat_store_load(uint32_t obj,void *dst,uint32_t max){return st_load(obj,dst,max);}
int plat_store_save(uint32_t obj,const void *src,uint32_t n){int result=st_save(obj,src,n);if(!result)store_writes++;return result;}
'''

def adapt(upstream,kind):
    if kind=='fomni':
        f=upstream/'host/omni_host.c';s=f.read_text()
        start=s.index('/* flash: one buffer per object, kept across a simulated reboot */')
        end=s.index('static uint32_t cpu_pct;',start)
        f.write_text(s[:start]+NOR+'\n'+s[end:])
    elif kind=='jangada':
        # Serialized 32-bit sample references remain offsets, never truncated host pointers.
        f=upstream/'firmware/src/eng_sample.c';s=f.read_text()
        old='base = (uint32_t)(uintptr_t)(smp_user_xip(k) + SMP_USER_DATA) - (uint32_t)(uintptr_t)SMP_DATA;'
        if s.count(old)!=1:raise SystemExit('Jangada sample offset anchor changed')
        f.write_text(s.replace(old,'base = 0x80000000u | ((SMP_USER_BASE + k * SMP_USER_SIZE) + SMP_USER_DATA);'))
        for name in ['eng_sample.c','eng_grain.c','eng_slice.c']:
            f=upstream/'firmware/src'/name;s,n=re.subn(r'SMP_DATA\[([^\]]+)\]',r'host_sample_byte(\1)',f.read_text())
            if n!=1:raise SystemExit('Jangada sample read anchor changed: '+name)
            f.write_text(s)

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--target',choices=TRIPLES,required=True);p.add_argument('--sdk',required=True);p.add_argument('--kind',choices=['fomni','jangada'])
    a=p.parse_args();lock=json.loads((HERE/'expansion.lock.json').read_text());out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    tc=Toolchain(a.target,a.sdk,llvm=True);cc=tc.cc;link=tc.link
    objects=[]
    for d in lock['firmwares']:
        kind=d['id']
        if a.kind and kind!=a.kind:continue
        if not d['generated_headers_sha256']:raise SystemExit('Missing exact generated resource pins')
        source=(a.source/kind).resolve();verify_expansion(source,d)
        repo=HERE.parents[1]
        for path in [source,out]:
            if not path.is_relative_to(repo) or subprocess.run(['git','-C',str(repo),'check-ignore','-q',str(path)]).returncode:
                raise SystemExit('Source/generated build outputs must stay Git-ignored inside the private repository')
        work=out/kind;upstream=work/'upstream';work.mkdir(exist_ok=True)
        for part in ['firmware','host']:
            if (source/part).exists():shutil.copytree(source/part,upstream/part,dirs_exist_ok=True)
        adapt(upstream,kind)
        wrapper=work/'native';wrapper.mkdir(exist_ok=True);shutil.copy2(HERE/(kind+'_core.c'),wrapper/(kind+'_core.c'))
        marker=work/'state-marker.h'
        marker.write_text('#include <stdint.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <stdio.h>\n#include <string.h>\n#include <math.h>\n#include <time.h>\n#pragma clang section bss="__DATA,__felbss" data="__DATA,__feldata"\n'.replace("__DATA,__felbss",tc.bss).replace("__DATA,__feldata",tc.data))
        common=['-target',TRIPLES[a.target],*tc.flags,'-O2','-std=gnu11','-fwrapv','-fno-strict-aliasing','-ffp-contract=off','-w','-include',str(marker),
                '-DFEL_PREFIX='+d['prefix'],*tc.sections,
                '-I'+str(HERE),'-I'+str(source/'build/gen'),'-I'+str(upstream/'firmware/src'),'-I'+str(upstream/'firmware/src/dsp')]
        units=[wrapper/(kind+'_core.c')]
        if kind=='fomni':common+=['-DOM_HOST','-DOM_VERSION="0.4"'];units.append(upstream/'firmware/src/dsp/omni.c')
        bitcodes=[]
        for i,unit in enumerate(units):
            bc=work/(str(i)+'.ll');bitcodes.append(bc)
            run(cc,*common,'-S','-emit-llvm','-Xclang','-disable-llvm-passes',unit,'-o',bc)
        merged=work/'merged.ll';namespaced=work/'namespaced.ll';state=work/'state.ll';obj=work/(kind+'.o')
        run(link,'-S',*bitcodes,'-o',merged);namespaced.write_text(namespace_ir(merged.read_text(),d['prefix']))
        run(sys.executable,HERE/'fel_state.py',namespaced,state,d['prefix'])
        run(cc,'-target',TRIPLES[a.target],*tc.flags,'-O2','-ffp-contract=off','-c',state,'-o',obj)
        objects.append(obj)
    run(*tc.ar,'crs',out/'libfm1_native_expansion.a',*objects)
if __name__=='__main__':main()
