#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Reproduce three synthetic host audio/Save/CRC/restart checks; no owner library I/O."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
from build import verify

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    root=args.source.resolve();out=args.out.resolve()
    research=REPO/'Research'
    if not root.is_relative_to(research) or not out.is_relative_to(research):
        raise SystemExit('Sources and synthetic test output must stay inside ignored Research/')
    out.mkdir(parents=True,exist_ok=True)
    compiler=subprocess.check_output(['xcrun','--sdk','macosx','--find','clang'],text=True).strip()
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    reports=[]
    for kind in ['ghoulbox','hortator','jiant']:
        d=json.loads((HERE/(kind+'.json')).read_text());source=root/kind;verify(source,d)
        work=out/kind;upstream=work/'upstream'
        for part in d['copy_dirs']:
            if (source/part).is_dir():
                shutil.copytree(source/part,upstream/part,dirs_exist_ok=True,ignore=shutil.ignore_patterns('build','__pycache__','.git'))
        adaptation=HERE/(kind+'_adapt.py')
        if adaptation.exists():
            spec=importlib.util.spec_from_file_location('host_adaptation',adaptation)
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.adapt(upstream)
        native=work/'native';native.mkdir(exist_ok=True)
        adapter=native/(kind+'.c');shutil.copy2(HERE/(kind+'.c'),adapter)
        binary=work/'roundtrip';checkpoint=work/'synthetic-checkpoint.bin'
        command=[compiler,'-isysroot',sdk,'-O1','-std=gnu11','-w','-fwrapv','-ffp-contract=off',
                 '-I'+str(source/'build/gen'),'-I'+str(upstream/'firmware/src'),'-I'+str(HERE.parent),
                 '-DFM1_TEST_ADAPTER="'+str(adapter)+'"',str(HERE/(kind+'_test.c')),'-o',str(binary)]
        subprocess.run(command,check=True)
        stages=[]
        for stage in ['write','read']:
            result=subprocess.run([str(binary),stage,str(checkpoint)],capture_output=True,text=True,timeout=60)
            (work/(stage+'.log')).write_text(result.stdout+result.stderr)
            if result.returncode:
                raise SystemExit(kind+' '+stage+' failed; see '+str(work/(stage+'.log')))
            stages.append({'stage':stage,'output':result.stdout.strip()})
        reports.append({'id':kind,'source_commit':d['commit'],'adapter_sha256':hashlib.sha256(adapter.read_bytes()).hexdigest(),
                        'checkpoint_sha256':hashlib.sha256(checkpoint.read_bytes()).hexdigest(),'stages':stages})
        print(kind+': Save/CRC/restart checks passed')
    (out/'report.json').write_text(json.dumps({'checks':reports},indent=2)+'\n')

if __name__=='__main__':main()
