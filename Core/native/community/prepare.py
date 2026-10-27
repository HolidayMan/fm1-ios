#!/usr/bin/env python3
"""Explicit opt-in fetch and generation for exact community source/resource pins."""
import argparse,hashlib,json,subprocess,sys,urllib.request
from pathlib import Path
from build import verify
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--kind');a=p.parse_args();root=a.source.resolve();repo=HERE.parents[2]
    if not root.is_relative_to(repo/'Research'):raise SystemExit('Prepared external files must stay under ignored Research/')
    descriptors=json.loads((HERE/'community.lock.json').read_text())['firmwares']
    for d in descriptors:
        if a.kind and d['id']!=a.kind:continue
        src=root/d['id']
        if not src.exists():
            root.mkdir(parents=True,exist_ok=True)
            if d.get('tag') and d['tag']!=d['commit']:
                subprocess.run(['git','clone','--depth','1','--branch',d['tag'],'--recurse-submodules',d['source'],str(src)],check=True)
            else:
                subprocess.run(['git','clone','--no-checkout',d['source'],str(src)],check=True)
                subprocess.run(['git','-C',str(src),'checkout','--detach',d['commit']],check=True)
                subprocess.run(['git','-C',str(src),'submodule','update','--init','--recursive'],check=True)
        if subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()!=d['commit']:raise SystemExit('Source pin mismatch '+d['id'])
        # Reject modified source/generators before executing any upstream code.
        verify(src,d,generated=False)
        (src/'build/gen').mkdir(parents=True,exist_ok=True)
        for command in d.get('generate_commands',[]):subprocess.run([sys.executable,*command],cwd=src,check=True)
        verify(src,d)
        target=root/d['package_filename']
        if not target.exists():
            with urllib.request.urlopen(d['package']['url'],timeout=60) as response:target.write_bytes(response.read())
        package=target.read_bytes()
        if len(package)!=d['package']['size'] or hashlib.sha256(package).hexdigest()!=d['package']['sha256']:raise SystemExit('Package fingerprint mismatch '+d['id'])
        print('Verified '+d['id']+' '+(d.get('tag') or d['commit']))
if __name__=='__main__':main()
