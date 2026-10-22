#!/usr/bin/env python3
"""Fetch exact Skiff source and generate pinned resources locally, never in the app."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
HERE=Path(__file__).resolve().parent
LOCK=json.loads((HERE/'skiff.lock.json').read_text())
RESEARCH=HERE.parents[1]/'Research'

def verify(source,generated=True):
    source=Path(source).resolve()
    if not source.is_relative_to(RESEARCH.resolve()):raise ValueError('Skiff source/assets must remain in ignored Research/')
    head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    if head!=LOCK['commit']:raise ValueError('Skiff requires exact v1.4 source commit '+LOCK['commit'])
    subprocess.run(['git','-C',str(source),'diff','--exit-code','HEAD'],check=True)
    for name,expected in LOCK['notices_sha256'].items():
        if hashlib.sha256((source/name).read_bytes()).hexdigest()!=expected:raise ValueError('Skiff notice changed: '+name)
    if generated:
        for name,expected in LOCK['generated_headers_sha256'].items():
            file=source/'build/gen'/name
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=expected:raise ValueError('Missing/corrupt pinned Skiff resource: '+name)
    return source

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--verify-only',action='store_true');a=p.parse_args()
    source=a.source.resolve()
    if not source.is_relative_to(RESEARCH.resolve()):raise ValueError('Skiff source/assets must remain in ignored Research/')
    if not source.exists():
        if a.verify_only:raise ValueError('Pinned Skiff source is missing')
        source.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['git','clone','--depth','1','--branch',LOCK['tag'],LOCK['source'],str(source)],check=True)
    verify(source,generated=False)
    if not a.verify_only:
        from PIL import features
        if not features.check('raqm'):raise ValueError('Build-only Pillow must support RAQM for exact upstream fonts')
        spec=importlib.util.spec_from_file_location('skiff_upstream_build',source/'tools/build.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.generate()
    verify(source)
    print('Verified exact Skiff v1.4 source and all eight generated resources at '+str(source))
if __name__=='__main__':
    try:main()
    except (ValueError,subprocess.CalledProcessError) as error:sys.exit(str(error))
