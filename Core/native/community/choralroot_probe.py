#!/usr/bin/env python3
"""Native ChoralRoot machine-code parity and derived-bank semantic checks."""
import argparse,hashlib,json,shutil,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import build
from choralroot_adapt import adapt
from choralroot_init_bank import derive,audit_object

def run(*args):subprocess.run([str(x) for x in args],check=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args()
    source=a.source.resolve();work=a.work.resolve();repo=HERE.parents[2]
    for path in [source,work]:
        if not path.is_relative_to(repo):raise SystemExit('Source/output must remain inside repository')
        run('git','-C',repo,'check-ignore','-q',path)
    d=json.loads((HERE/'choralroot.lock.json').read_text());build.verify(source,d)
    package=source.parent/d['package_filename']
    if len(package.read_bytes())!=d['package']['size'] or hashlib.sha256(package.read_bytes()).hexdigest()!=d['package']['sha256']:raise SystemExit('Package differs')
    work.mkdir(parents=True,exist_ok=True);upstream=work/'upstream'
    if upstream.exists():shutil.rmtree(upstream)
    for part in d['copy_dirs']:shutil.copytree(source/part,upstream/part,ignore=shutil.ignore_patterns('.git','build','__pycache__'))
    resources=work/'resources'
    if resources.exists():shutil.rmtree(resources)
    derive(upstream,resources,source,d)
    # Same INIT derivation, otherwise untouched upstream serial C web entry.
    # Its __EMSCRIPTEN__ branches select portable RAM+serial HAL only; this is
    # compiled native machine code with no WASM, JS or web runtime.
    tc=build.Toolchain('aarch64-apple-darwin','macosx',llvm=True)
    flags=['-target',tc.triple,*tc.flags,'-O2','-std=gnu11','-w','-fwrapv','-fno-strict-aliasing','-ffp-contract=off']
    ref=work/'reference.dylib'
    run(tc.cc,*flags,'-D__EMSCRIPTEN__','-DEMU_WEB','-DFELUCCA_P5_FACTORY=0','-DFELUCCA_VERSION="ChoralRoot 0.27"','-I'+str(upstream/'tools/emu/web/compat'),'-I'+str(resources),'-I'+str(upstream/'firmware/src'),'-dynamiclib',upstream/'tools/emu/web/emu_web.c','-o',ref)
    adapt(upstream);native=work/'native';native.mkdir(exist_ok=True)
    unit=native/'choralroot.c';unit.write_text((HERE/'choralroot.c').read_text()+'\n'+(HERE/'choralroot_test_api.h').read_text())
    ll,ns,state=[work/n for n in ['core.ll','namespace.ll','state.ll']]
    run(tc.cc,*flags,'-DFEL_PREFIX=chr_',*tc.sections,'-I'+str(HERE.parent),'-I'+str(resources),'-I'+str(upstream/'firmware/src'),'-S','-emit-llvm','-Xclang','-disable-llvm-passes',unit,'-o',ll)
    ns.write_text(build.namespace_ir(ll.read_text(),'chr_'));run(sys.executable,HERE.parent/'fel_state.py',ns,state,'chr_')
    obj=work/'choralroot.o';lib=work/'choralroot.dylib'
    run(tc.cc,*flags,'-c',state,'-o',obj);audit_object(obj,d)
    run(tc.cc,*flags,'-dynamiclib',obj,'-o',lib)
    run(sys.executable,HERE/'choralroot_test.py','--library',lib,'--reference',ref,'-v')
if __name__=='__main__':main()
