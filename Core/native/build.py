#!/usr/bin/env python3
"""Build exact pinned SLOOP as a native library. External firmware stays ignored/local."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
from target_config import Toolchain

HERE = pathlib.Path(__file__).resolve().parent

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=pathlib.Path, required=True)
    p.add_argument('--out', type=pathlib.Path, required=True)
    p.add_argument('--target', required=True)
    p.add_argument('--sdk', required=True)
    p.add_argument('--fixture-input', type=pathlib.Path)
    p.add_argument('--fixture-output', type=pathlib.Path)
    p.add_argument('--fixture-variant', type=int, choices=range(3), default=0)
    a = p.parse_args()
    source = a.source.resolve()
    head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    lock = json.loads((HERE / 'upstream.lock.json').read_text())
    pin = lock['sloop']
    if head != pin['commit']:
        sys.exit('native SLOOP requires exact '+pin['tag']+' source commit '+pin['commit'])
    run('git', '-C', source, 'diff', '--exit-code', 'HEAD', '--', 'firmware', 'tools', 'assets')
    generated = source / 'build/generated'
    package = source / pin['package']['path']
    if (not package.is_file() or package.stat().st_size != pin['package']['size'] or
            hashlib.sha256(package.read_bytes()).hexdigest() != pin['package']['sha256']):
        sys.exit('Missing/corrupt exact SLOOP release package')
    for name, expected in lock['sloop']['generated_headers_sha256'].items():
        file = generated / name
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            sys.exit('Missing/corrupt exact SLOOP generated resource: ' + name + '; rerun native/prepare.py')
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    upstream = out / 'upstream/firmware'
    shutil.copytree(source / 'firmware', upstream, dirs_exist_ok=True)
    # Preserve the firmware's 32-bit serialized sample offsets on a 64-bit host.
    sample = upstream / 'src/eng_sample.c'
    text = sample.read_text().replace(
        'base = (uint32_t)(uintptr_t)(smp_user_xip(k) + SMP_USER_DATA) - (uint32_t)(uintptr_t)SMP_DATA;',
        'base = 0x80000000u | (SMP_USER_OFF(k) + SMP_USER_DATA);')
    if 'base = 0x80000000u' not in text:
        sys.exit('native SLOOP sample-offset patch no longer matches pinned source')
    sample.write_text(text)
    for name in ['eng_sample.c', 'eng_grain.c', 'eng_slice.c']:
        file = upstream / 'src' / name
        text = file.read_text()
        import re
        text, n = re.subn(r'SMP_DATA\[([^\]]+)\]', r'host_sample_byte(\1)', text)
        if n != 1:
            sys.exit('native SLOOP expected exactly one sample read in ' + name)
        file.write_text(text)
    wrapper = out / 'native'
    wrapper.mkdir(exist_ok=True)
    shutil.copy2(HERE / 'sloop_core.c', wrapper / 'sloop_core.c')
    tc = Toolchain(a.target, a.sdk)
    clang, triple = tc.cc, tc.triple
    if a.fixture_output:
        if a.target != 'aarch64-apple-darwin' or not a.fixture_input:
            sys.exit('Fixture generation requires host target and a fresh firmware-only base flash')
        base = a.fixture_input.resolve(strict=True)
        destination = a.fixture_output.resolve()
        research = HERE.parents[1] / 'Research'
        if not destination.is_relative_to(research.resolve()) or destination.exists() or destination == base:
            sys.exit('Synthetic fixture output must be a NEW file under ignored Research/')
        if hashlib.sha256(base.read_bytes()).hexdigest() != lock['synthetic_fixture_base_flash_sha256']:
            sys.exit('Synthetic fixture input must be the exact fresh firmware-only raw flash, never an owner save')
        program = wrapper / 'fixture.c' 
        program.write_text('#include <stdio.h>\n#include "sloop_core.c"\n' +
            '#include "' + str(HERE / 'stress_fixture.inc') + '"\n' +
            'int main(int argc,char**argv){ if(argc!=3)return 1; FILE*f=fopen(argv[1],"rb");' +
            'if(!f||fread(host_flash,1,HOST_FLASH_SIZE,f)!=HOST_FLASH_SIZE)return 2;fclose(f);slp_init();' +
            'if(fm1_stress_fixture_prepare(' + str(a.fixture_variant) + '))return 3;' +
            'f=fopen(argv[2],"wb");if(!f)return 4;size_t n=fwrite(host_flash,1,HOST_FLASH_SIZE,f);' +
            'fclose(f);return n==HOST_FLASH_SIZE?0:5;}\n')
        executable = out / 'make-fixture'
        run(clang, '-target', triple, *tc.flags, '-O2', '-std=gnu11', '-w', '-fwrapv', '-fno-strict-aliasing',
            '-DFEL_PREFIX=slp_', '-DFEL_BSS_SECTION="__DATA,__felbss"',
            '-DFEL_DATA_SECTION="__DATA,__feldata"', '-I' + str(HERE), '-I' + str(generated),
            program, '-o', executable)
        a.fixture_output.parent.mkdir(parents=True, exist_ok=True)
        run(executable, a.fixture_input.resolve(strict=True), a.fixture_output.resolve())
        return
    run(sys.executable, HERE / 'fel_state_build.py', '--cc', clang,
        '--src', wrapper / 'sloop_core.c', '--out', out / 'sloop.o',
        '--prefix', 'slp_', '--work', out / 'llvm', '--target', triple,
        *['--flag='+f for f in tc.flags], '--flag=-fwrapv', '--flag=-fno-strict-aliasing',
        '-DFEL_PREFIX=slp_', *tc.sections, '-I' + str(HERE), '-I' + str(generated))
    run(*tc.ar, 'crs', out / 'libfm1_native_sloop.a', out / 'sloop.o')

if __name__ == '__main__':
    main()
