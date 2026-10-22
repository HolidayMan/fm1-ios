#!/usr/bin/env python3
"""Compile pinned community firmware source; generated assets stay under ignored Research/."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
from target_config import Toolchain, TRIPLES
X0X_SOURCES = ['dsp/drum909.c','dsp/drum808.c','dsp/bass303.c','dsp/breaks.c','dsp/fxbus.c',
               'dsp/master.c','seq/sequencer.c','seq/tb3po.c','seq/pattern.c','seq/motion.c','app/engine.c']

def run(*args):
    subprocess.run([str(x) for x in args],check=True)

def validate(source, descriptor):
    head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    if head != descriptor['commit']:
        raise SystemExit('Source pin mismatch: '+descriptor['id'])
    run('git','-C',source,'diff','--exit-code','HEAD','--','firmware','tools','assets','fonts','web/fukiai.ttf')
    for name,want in descriptor.get('notices_sha256',{}).items():
        if hashlib.sha256((source/name).read_bytes()).hexdigest()!=want:raise SystemExit('Source notice mismatch '+descriptor['id']+'/'+name)
    for module,commit in descriptor.get('submodules',{}).items():
        actual=subprocess.check_output(['git','-C',str(source/module),'rev-parse','HEAD'],text=True).strip()
        if actual!=commit:raise SystemExit('Submodule pin mismatch: '+module)
        run('git','-C',source/module,'diff','--exit-code','HEAD')
    for name,want in descriptor['generated_headers_sha256'].items():
        if name in descriptor.get('derived_soundset',{}).get('excluded_generated_headers',[]):continue
        p=source/'build/gen'/name
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=want:
            raise SystemExit('Missing/corrupt exact generated resource '+descriptor['id']+'/'+name)

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,required=True)
    p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--target',required=True)
    p.add_argument('--sdk',required=True);p.add_argument('--kind',choices=['felucca','x0x','melodee'])
    a=p.parse_args();lock=json.loads((HERE/'family.lock.json').read_text())
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    tc=Toolchain(a.target,a.sdk)
    clang=tc.cc
    objects=[]
    for d in lock['firmwares']:
        kind=d['id']
        if a.kind and kind!=a.kind:continue
        source=(a.source/kind).resolve();validate(source,d)
        work=out/kind;upstream=work/'upstream';work.mkdir(exist_ok=True)
        shutil.copytree(source/'firmware',upstream/'firmware',dirs_exist_ok=True)
        if kind=='felucca':
            # Upstream serialized sample references are 32-bit; reserve a virtual range
            # instead of truncating a host pointer when taking the user slot difference.
            f=upstream/'firmware/src/eng_sample.c';s=f.read_text()
            old='base = (uint32_t)(uintptr_t)(smp_user_xip(k) + SMP_USER_DATA) - (uint32_t)(uintptr_t)SMP_DATA;'
            if old not in s:raise SystemExit('Felucca sample offset adaptation no longer matches')
            f.write_text(s.replace(old,'base = 0x80000000u | ((SMP_USER_BASE + (k) * SMP_USER_SIZE) + SMP_USER_DATA);'))
            import re
            for name in ['eng_sample.c','eng_grain.c','eng_slice.c']:
                f=upstream/'firmware/src'/name;s=f.read_text();s,n=re.subn(r'SMP_DATA\[([^\]]+)\]',r'host_sample_byte(\1)',s)
                if n!=1:raise SystemExit('Expected one sample read in '+name)
                f.write_text(s)
        if kind=='x0x':
            engine=upstream/'firmware/src/app/engine.c'
            engine.write_text(engine.read_text()+"\n/* Read-only native workload diagnostics; no sound/scheduling change. */\nuint32_t fm1_x0x_native_part_mask(void) {return (drum909_active(&d909)?1u:0u)|(drum808_active(&d808)?2u:0u)|(!b303[0].idle?4u:0u)|(!b303[1].idle?8u:0u)|(brk.running && brk.gate>0.0f?16u:0u); }\n")
        wrapper=work/'native';wrapper.mkdir(exist_ok=True)
        shutil.copy2(HERE/(kind+'_core.c'),wrapper/(kind+'_core.c'))
        flags=[*tc.flags,'-fwrapv','-fno-strict-aliasing','-ffp-contract=off']
        resource_dir=source/'build/gen'
        if kind=='melodee':
            from melodee_init_bank import derive,EXCLUDED
            resource_dir=work/'resources'
            if resource_dir.exists():shutil.rmtree(resource_dir)
            resource_dir.mkdir()
            for name in d['generated_headers_sha256']:
                if name not in EXCLUDED:shutil.copy2(source/'build/gen'/name,resource_dir/name)
            derived=derive(upstream,resource_dir,d)
            receipt={'soundset':d['derived_soundset'],'source_commit':d['commit'],
                     'derived_files_sha256':derived,
                     'compiled_resources_sha256':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in resource_dir.iterdir()},
                     'excluded_upstream_resources_sha256':{name:d['generated_headers_sha256'][name] for name in sorted(EXCLUDED)}}
            (work/'init-bank-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        defines=['-DFEL_PREFIX='+d['prefix'],*tc.sections,
                 '-I'+str(HERE),'-I'+str(resource_dir)]
        obj=work/(kind+'.o')
        if kind!='x0x':
            run(sys.executable,HERE/'fel_state_build.py','--cc',clang,'--src',wrapper/(kind+'_core.c'),
                '--out',obj,'--prefix',d['prefix'],'--work',work/'llvm','--target',TRIPLES[a.target],
                *['--flag='+f for f in flags],*defines)
        else:
            # LLVM links all real upstream DSP translation units before the exact same
            # state isolation pass, so writable DSP statics cannot leak between instances.
            linked_tc=Toolchain(a.target,a.sdk,llvm=True);cc=linked_tc.cc;link=linked_tc.link
            marker=work/'state-marker.h'
            marker.write_text('#include <stdint.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <string.h>\n#include <math.h>\n#include <time.h>\n#pragma clang section bss="__DATA,__felbss" data="__DATA,__feldata"\n'.replace("__DATA,__felbss",tc.bss).replace("__DATA,__feldata",tc.data))
            common=['-target',TRIPLES[a.target],*flags,'-O2','-std=gnu11','-w','-include',marker,*defines,
                    '-DX0X_HOST','-DX0X_VERSION="1.1.0"','-I'+str(upstream/'firmware/src'),'-I'+str(upstream/'firmware/src/dsp')]
            units=[wrapper/'x0x_core.c']+[upstream/'firmware/src'/x for x in X0X_SOURCES]
            bitcodes=[]
            for i,unit in enumerate(units):
                bc=work/(str(i)+'.bc');bitcodes.append(bc)
                run(cc,*common,'-S','-emit-llvm','-Xclang','-disable-llvm-passes',unit,'-o',bc)
            merged=work/'merged.ll';rewritten=work/'state.ll'
            run(link,'-S',*bitcodes,'-o',merged)
            run(sys.executable,HERE/'fel_state.py',merged,rewritten,d['prefix'])
            run(cc,'-target',TRIPLES[a.target],*flags,'-O2','-c',rewritten,'-o',obj)
        if kind=='melodee':
            from melodee_init_bank import audit_object
            receipt['excluded_object_payload_checks']=audit_object(obj,d)
            (work/'init-bank-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        objects.append(obj)
    run(*tc.ar,'crs',out/'libfm1_native_family.a',*objects)

if __name__=='__main__':main()
