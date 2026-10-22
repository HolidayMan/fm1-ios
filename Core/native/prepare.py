#!/usr/bin/env python3
"""Fetch exact local SLOOP resources. Run with a Python that has Pillow installed."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
HERE=Path(__file__).resolve().parent
lock=json.loads((HERE/'upstream.lock.json').read_text())['sloop']
if len(sys.argv)!=2: sys.exit('usage: prepare.py ABSOLUTE_IGNORED_SOURCE_DIRECTORY')
source=Path(sys.argv[1]).resolve()
if not source.exists():
    source.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['git','clone','--depth','1','--branch',lock['tag'],lock['source'],str(source)],check=True)
head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
if head!=lock['commit']: sys.exit('source is not pinned SLOOP '+lock['commit'])
subprocess.run(['git','-C',str(source),'diff','--exit-code','HEAD','--','firmware','tools','assets'],check=True)
# Exact upstream generators. Pillow is a build-only dependency, never an app dependency.
spec=importlib.util.spec_from_file_location('sloop_build',source/'tools/build.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.GEN=source/'build/generated';module.generate()
import hashlib
for name,expected in lock['generated_headers_sha256'].items():
    if hashlib.sha256((module.GEN/name).read_bytes()).hexdigest()!=expected: sys.exit('generated hash mismatch: '+name)
package=source/lock['package']['path']
if package.stat().st_size != lock['package']['size'] or hashlib.sha256(package.read_bytes()).hexdigest()!=lock['package']['sha256']:
    sys.exit('release package hash/size mismatch')
print('Verified exact SLOOP '+lock['tag']+' source, package and all seven generated resources at '+str(source))
