#!/usr/bin/env python3
"""Fetch exact additional source pins and reproduce their own generated resources locally."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from expansion_build import verify_expansion
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--kind',choices=['fomni','jangada']);a=p.parse_args()
    root=a.source.resolve();research=HERE.parents[1]/'Research'
    if not root.is_relative_to(research.resolve()):raise SystemExit('Source/resources must remain under ignored Research/')
    lock=json.loads((HERE/'expansion.lock.json').read_text())
    for d in lock['firmwares']:
        if a.kind and a.kind!=d['id']:continue
        src=root/d['id']
        if not src.exists():
            root.mkdir(parents=True,exist_ok=True);subprocess.run(['git','clone','--depth','1','--branch',d['tag'],d['source'],str(src)],check=True)
        head=subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()
        if head!=d['commit']:raise SystemExit('Source pin mismatch '+d['id'])
        subprocess.run(['git','-C',str(src),'diff','--exit-code','HEAD'],check=True)
        gen=src/'build/gen';gen.mkdir(parents=True,exist_ok=True)
        if d['id']=='fomni':
            commands=[['tools/gen_font.py',str(gen/'felucca_font.h')],['tools/gen_words.py','firmware/words.tsv','web/words',str(gen/'ann_words.h')]]
        else:
            commands=[['tools/gen_aa_font.py',str(gen/'ui_fonts.h'),'--preset','jangada'],['tools/gen_aa_icons.py',str(gen/'ui_icons.h'),'--font','assets/fonts/fukiai.ttf','--sizes','12','--legacy-only'],['tools/gen_ui_palettes.py',str(gen/'ui_palettes.h')],['tools/gen_tables.py',str(gen/'felucca_tables.h')],['tools/gen_samples.py',str(gen/'felucca_samples.h')],['tools/gen_drumkits.py',str(gen/'felucca_drumkits.h')],['tools/gen_fm6_patches.py',str(gen/'felucca_fm6.h')]]
        # Serial generation avoids competing with interactive profiling/build work.
        for command in commands:subprocess.run([sys.executable,*command],cwd=src,check=True)
        verify_expansion(src,d);print('Verified '+d['id']+' '+d['tag'])
if __name__=='__main__':main()
