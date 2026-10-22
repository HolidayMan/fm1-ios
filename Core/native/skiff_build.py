#!/usr/bin/env python3
"""Build Skiff's pinned actual source application, ISR and DSP with native host I/O."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from skiff_prepare import HERE,LOCK,verify
from official_preview_prepare import ignored_path
from target_config import Toolchain

def run(*args):subprocess.run([str(value) for value in args],check=True)
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--target',required=True);p.add_argument('--sdk',required=True);a=p.parse_args()
    source=verify(a.source);out=ignored_path(a.out)
    tc=Toolchain(a.target,a.sdk);triple=tc.triple;out.mkdir(parents=True,exist_ok=True)
    upstream=out/'upstream';shutil.copytree(source/'firmware',upstream/'firmware',dirs_exist_ok=True)
    for relative in ['tests/hostsim.c','web/emu/felucca_web.c']:
        to=upstream/relative;to.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/relative,to)
    sample=upstream/'firmware/src/eng_sample.c';text=sample.read_text()
    old='base = (uint32_t)(uintptr_t)(smp_user_xip(k) + SMP_USER_DATA) - (uint32_t)(uintptr_t)SMP_DATA;'
    if text.count(old)!=1:sys.exit('Skiff sample-offset adaptation no longer matches')
    sample.write_text(text.replace(old,'base = 0x80000000u | (SMP_USER_BASE + k * SMP_USER_SIZE + SMP_USER_DATA);'))
    for name,count in LOCK['sample_offset_patches'].items():
        file=upstream/'firmware/src'/name;text,n=re.subn(r'SMP_DATA\[([^\]]+)\]',r'skf_host_sample_byte(\1)',file.read_text())
        if n!=count:sys.exit('Skiff expected sample reads no longer match: '+name)
        file.write_text(text)
    host=upstream/'tests/hostsim.c';text=host.read_text();anchor='int main(int argc, char **argv)'
    if text.count(anchor)!=1:sys.exit('Skiff host benchmark entry no longer matches')
    host.write_text(text.replace(anchor,'static '+anchor))
    native=out/'native';native.mkdir(exist_ok=True);shutil.copy2(HERE/'skiff_core.c',native/'skiff_core.c')
    tc.adapt_wrapper(native/'skiff_core.c')
    clang=tc.cc
    flags=['-target',triple,*tc.flags,'-std=gnu11','-O2','-w','-fwrapv','-fno-strict-aliasing','-ffp-contract=off','-DFELUCCA_VERSION="v1.4"','-I'+str(source/'build/gen'),'-I'+str(upstream/'firmware/src')]
    run(clang,*flags,'-S','-emit-llvm','-Xclang','-disable-llvm-passes',native/'skiff_core.c','-o',out/'core.ll')
    text=(out/'core.ll').read_text()
    names=set(re.findall(r'^define .*?@([\w.$]+)\(',text,re.M))|set(re.findall(r'^@([\w.$]+) = (?!external\b)',text,re.M))
    rename={name:'skf_up_'+name for name in names if not name.startswith(('skf_','llvm.','.'))}
    text=re.sub(r'@([\w.$]+)',lambda m:'@'+rename.get(m[1],m[1]),text)
    (out/'namespaced.ll').write_text(text)
    run(sys.executable,HERE/'fel_state.py',out/'namespaced.ll',out/'state.ll','skf_')
    run(clang,'-target',triple,*tc.flags,'-O2','-c',out/'state.ll','-o',out/'skiff.o')
    archive=out/'libfm1_native_skiff.a';run(*tc.ar,'crs',archive,out/'skiff.o')
    receipt={'schema_version':1,'id':'skiff','source':LOCK['source'],'commit':LOCK['commit'],'package':LOCK['package'],'target':triple,'flash_bytes':LOCK['flash_bytes'],'state_alignment':LOCK['state_alignment'],'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'generated_headers_sha256':LOCK['generated_headers_sha256'],'adapter_sha256':{name:hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in ['skiff_core.c','skiff_build.py','skiff_prepare.py','skiff.lock.json','fel_state.py','target_config.py']}}
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print('Built pinned Skiff1.4 actual application/ISR/DSP native host; no hardware parity acceptance claimed.')
if __name__=='__main__':
    try:main()
    except (ValueError,subprocess.CalledProcessError) as error:sys.exit(str(error))
