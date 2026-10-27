#!/usr/bin/env python3
"""Build pinned source-native community engines; never download or repair inputs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent
NATIVE=HERE.parent
sys.path.insert(0,str(NATIVE))
from target_config import Toolchain,TRIPLES
from expansion_build import namespace_ir


def run(*args,**kwargs):
    subprocess.run([str(x) for x in args],check=True,**kwargs)


def inputs(source,dirs):
    return {str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest()
            for directory in dirs for p in sorted((source/directory).rglob('*'))
            if p.is_file() and not {'.git','build','__pycache__'}.intersection(p.relative_to(source).parts)
            and p.suffix!='.pyc' and not ('web' in p.relative_to(source).parts and 'words' in p.relative_to(source).parts)}


def verify(source,d,generated=True):
    if subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()!=d['commit']:
        raise SystemExit('Source pin mismatch: '+d['id'])
    run('git','-C',source,'diff','--exit-code','HEAD')
    for sub,commit in d.get('submodules',{}).items():
        if subprocess.check_output(['git','-C',str(source/sub),'rev-parse','HEAD'],text=True).strip()!=commit:
            raise SystemExit('Submodule pin mismatch: '+d['id']+'/'+sub)
        run('git','-C',source/sub,'diff','--exit-code','HEAD')
    if inputs(source,d['input_dirs'])!=d['inputs']:
        raise SystemExit('Exact source/resource input set differs: '+d['id'])
    for path,want in (d['generated_headers_sha256'] if generated else {}).items():
        file=source/'build/gen'/path
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=want:
            raise SystemExit('Missing/changed generated resource: '+d['id']+'/'+path)
    for path,want in d['notices_sha256'].items():
        if hashlib.sha256((source/path).read_bytes()).hexdigest()!=want:
            raise SystemExit('Changed license notice: '+d['id']+'/'+path)


def registry(descriptors):
    """Only public package fingerprints and a fixed compiled ABI enter Rust."""
    out=[]
    funcs=[('state_size','()->u64'),('state_init','(state:*mut u8)->i32'),('bind','(state:*mut u8)'),('init','()'),('ctl','()->u32'),('rate','()->u32'),('render','(out:*mut i32,frames:u32)'),('draw','(out:*mut u16)'),('physical_key','(id:u32,down:i32)'),('release_all','()'),('physical_encoder','(id:u32,delta:i32)'),('physical_leds','(out:*mut f32)'),('volume','(value:u32)'),('flash_load','(data:*const u8)'),('flash_copy','(out:*mut u8)'),('workload_metrics','(out:*mut u64,capacity:u32)->u32')]
    fields={'key':'physical_key','encoder':'physical_encoder','leds':'physical_leds','metrics':'workload_metrics'}
    for d in descriptors:
        out += ['mod '+d['id']+' {','use crate::native_sloop::Api;','extern "C" {']
        for name,sig in funcs:out += ['#[link_name="'+d['prefix']+name+'"] fn '+name+sig+';']
        out += ['}','pub(super) const API:Api=Api {','kind:'+str(d['kind'])+',flash_size:'+str(d['flash_bytes'])+',alignment:'+str(d['state_alignment'])+',']
        for field in ['state_size','state_init','bind','init','ctl','rate','render','draw','key','release_all','encoder','leds','volume','flash_load','flash_copy','metrics']:
            out += [field+':'+fields.get(field,field)+',']
        out += ['destroy:None,};','}']
    out += ['pub(super) fn for_digest(digest:[u8;32],len:usize)->Option<crate::native_sloop::Api> {']
    for d in descriptors:
        out += ['if (len==0 || len=='+str(d['package']['size'])+') && digest=='+str(list(bytes.fromhex(d['package']['sha256'])))+' {return Some('+d['id']+'::API);}']
    out += ['None','}','#[cfg(test)] pub(super) const FIXTURES:&[(u32,&str)]=&[']
    for d in descriptors:out+=['('+str(d['kind'])+',"'+d['package_filename']+'"),']
    out += ['];']
    return '\n'.join(out)+'\n'


def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--target',choices=TRIPLES,required=True);p.add_argument('--sdk',required=True);p.add_argument('--kind');a=p.parse_args()
    lock=json.loads((HERE/'community.lock.json').read_text())
    selected=[d for d in lock['firmwares'] if not a.kind or d['id']==a.kind]
    if not selected:raise SystemExit('No pinned community engines selected')
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    tc=Toolchain(a.target,a.sdk,llvm=True);objects=[]
    for d in selected:
        source=(a.source/d['id']).resolve()
        repo=NATIVE.parents[1]
        for path in (source,out):
            if not path.is_relative_to(repo) or subprocess.run(['git','-C',str(repo),'check-ignore','-q',str(path)]).returncode:
                raise SystemExit('Source/generated outputs must remain Git-ignored inside the repository')
        verify(source,d)
        work=out/d['id'];upstream=work/'upstream';work.mkdir(exist_ok=True)
        obj=work/(d['id']+'.o');cache=work/'verified-object.json'
        key=hashlib.sha256(json.dumps(d,sort_keys=True).encode())
        for file in [Path(__file__),NATIVE/'fel_state.py',NATIVE/'expansion_build.py',NATIVE/'target_config.py',NATIVE/'felucca_core.h',NATIVE/'felucca_core_api.h',HERE/(d['id']+'.c'),HERE/(d['id']+'_adapt.py'),HERE/'fm1base_adapt.py']:
            if file.exists():key.update(file.read_bytes())
        key.update(json.dumps([a.target,a.sdk,str(tc.cc),tc.flags],sort_keys=True).encode())
        fingerprint=key.hexdigest()
        previous=json.loads(cache.read_text()) if cache.exists() else {}
        if obj.exists() and previous.get('inputs')==fingerprint and previous.get('object')==hashlib.sha256(obj.read_bytes()).hexdigest():
            objects.append(obj);continue
        if upstream.exists():shutil.rmtree(upstream)
        for part in d['copy_dirs']:
            if (source/part).is_dir():shutil.copytree(source/part,upstream/part,ignore=shutil.ignore_patterns('.git','build','__pycache__'))
        adapt=HERE/(d['id']+'_adapt.py')
        if adapt.exists():
            spec=importlib.util.spec_from_file_location('community_adapt',adapt);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.adapt(upstream)
        wrapper=work/'native';wrapper.mkdir(exist_ok=True);unit=wrapper/(d['id']+'.c');shutil.copy2(HERE/(d['id']+'.c'),unit)
        marker=work/'state-marker.h';marker.write_text('#include <stdint.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <stdio.h>\n#include <string.h>\n#include <math.h>\n#include <time.h>\n#pragma clang section bss="'+tc.bss+'" data="'+tc.data+'"\n')
        flags=['-target',TRIPLES[a.target],*tc.flags,'-O2','-std=gnu11','-fwrapv','-fno-strict-aliasing','-ffp-contract=off','-w','-include',str(marker),'-DFEL_PREFIX='+d['prefix'],*tc.sections,'-I'+str(NATIVE),'-I'+str(HERE),'-I'+str(source/'build/gen')]
        flags += ['-I'+str(upstream/x) for x in d.get('include_dirs',[])]
        flags += d.get('defines',[])
        bitcodes=[]
        for i,u in enumerate([unit]+[upstream/x for x in d.get('extra_units',[])]):
            bc=work/(str(i)+'.ll');bitcodes.append(bc);run(tc.cc,*flags,'-S','-emit-llvm','-Xclang','-disable-llvm-passes',u,'-o',bc)
        merged=work/'merged.ll';namespaced=work/'namespaced.ll';state=work/'state.ll';obj=work/(d['id']+'.o')
        run(tc.link,'-S',*bitcodes,'-o',merged);namespaced.write_text(namespace_ir(merged.read_text(),d['prefix']))
        run(sys.executable,NATIVE/'fel_state.py',namespaced,state,d['prefix'])
        run(tc.cc,'-target',TRIPLES[a.target],*tc.flags,'-O2','-ffp-contract=off','-c',state,'-o',obj);objects.append(obj)
        cache.write_text(json.dumps({'inputs':fingerprint,'object':hashlib.sha256(obj.read_bytes()).hexdigest()})+'\n')
    run(*tc.ar,'crs',out/'libfm1_native_community.a',*objects)
    (out.parent/'community_registry.rs').write_text(registry(selected))

if __name__=='__main__':main()
