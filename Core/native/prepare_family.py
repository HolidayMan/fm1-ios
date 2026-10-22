#!/usr/bin/env python3
"""Fetch pinned source and generate exact resources locally (build-only Pillow+RAQM/fonttools)."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--generate-one',choices=['felucca','x0x','melodee'])
    a=p.parse_args();lock=json.loads((HERE/'family.lock.json').read_text())
    root=a.source.resolve();research=HERE.parents[1]/'Research'
    if not root.is_relative_to(research.resolve()):raise SystemExit('Native source/assets must stay in ignored Research/')
    selected=[d for d in lock['firmwares'] if not a.generate_one or d['id']==a.generate_one]
    for d in selected:
        src=root/d['id']
        if not src.exists():
            root.mkdir(parents=True,exist_ok=True)
            subprocess.run(['git','clone','--depth','1','--branch',d['tag'],d['source'],str(src)],check=True)
        if subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()!=d['commit']:
            raise SystemExit('Source pin mismatch '+d['id'])
        for name,want in d.get('notices_sha256',{}).items():
            if hashlib.sha256((src/name).read_bytes()).hexdigest()!=want:raise SystemExit('Source notice mismatch '+d['id']+'/'+name)
        if d.get('submodules'):subprocess.run(['git','-C',str(src),'submodule','update','--init','--recursive'],check=True)
        subprocess.run(['git','-C',str(src),'diff','--exit-code','HEAD'],check=True)
        if not a.generate_one:
            # Each upstream tool owns common module names such as fm1pkg_make.
            subprocess.run([sys.executable,str(HERE/'prepare_family.py'),str(root),'--generate-one',d['id']],check=True)
            continue
        from PIL import features
        if not features.check('raqm'):raise SystemExit('Build-only Pillow must support RAQM for exact upstream UI fonts')
        spec=importlib.util.spec_from_file_location('upstream_build',src/'tools/build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        if d['id']=='melodee':
            # The derived bank never reads the excluded .syx files or generators.
            m.GEN.mkdir(parents=True,exist_ok=True)
            generators=[('gen_aa_font.py','ui_fonts.h','--preset','rubik'),('gen_icons.py','ui_icons.h'),
                        ('gen_aa_keycaps.py','ui_keycaps.h'),('gen_ui_palettes.py','ui_palettes.h'),
                        ('gen_tables.py','melodee_tables.h'),('gen_fm6_patches.py','melodee_fm6.h'),
                        ('gen_909_tables.py','x0x_drum_tables.h')]
            subprocess.run([sys.executable,str(src/'tools/gen_scales.py'),'--check'],check=True)
            for script,output,*extra in generators:
                subprocess.run([sys.executable,str(src/'tools'/script),str(m.GEN/output),*extra],check=True)
        else:m.generate()
        for name,want in d['generated_headers_sha256'].items():
            if name in d.get('derived_soundset',{}).get('excluded_generated_headers',[]):continue
            file=src/'build/gen'/name
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=want:raise SystemExit('Exact generated resource mismatch '+d['id']+'/'+name)
        print('Verified '+d['id']+' '+d['tag']+' all generated resources')
if __name__=='__main__':main()
