#!/usr/bin/env python3
"""Compile exact public FM1 Open V14 browser sources as a native preview.

No opaque PI32v2 SDK archive participates. Output and downloaded source must stay
Git-ignored. Requires LLVM 20 clang/llvm-link for the pre-optimization IR rewrite.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from official_preview_prepare import HERE, LOCK, ignored_path, verify
from target_config import Toolchain, TRIPLES


def run(*args):
    subprocess.run([str(value) for value in args], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--target', choices=TRIPLES, required=True)
    p.add_argument('--sdk', choices=['macosx', 'iphoneos', 'iphonesimulator', 'android'], required=True)
    args = p.parse_args()
    source = verify(args.source)
    out = ignored_path(args.out)
    tc = Toolchain(args.target, args.sdk, llvm=True)
    triple, compiler, linker = tc.triple, tc.cc, tc.link
    version = subprocess.check_output([str(compiler), '--version'], text=True)
    if not re.search(r'clang version 20\.', version):
        sys.exit('Official preview requires LLVM 20; set FM1_NATIVE_LLVM_BIN explicitly.')
    if not linker.is_file():
        sys.exit('Official preview requires llvm-link beside the selected clang.')
    out.mkdir(parents=True, exist_ok=True)
    sources = sorted(source / name for name in LOCK['inputs'] if name.endswith('.c'))
    host_header = HERE / 'official_preview_host.h'
    if tc.android:
        host_header = out / 'official_preview_host.h'
        host_header.write_text((HERE / 'official_preview_host.h').read_text().replace('__DATA,__ofpbss', '.ofpbss').replace('__DATA,__ofpdata', '.ofpdata'))
    flags = ['-target', triple, *tc.flags, '-std=gnu11', '-O2', '-fwrapv',
             '-fno-fast-math', '-ffp-contract=off', '-DFM1_HOST_TEST', '-DFM1_OPEN_WEB',
             '-Wno-unknown-attributes', '-include', str(host_header)]
    for directory in ['web/engine', 'web/synth', 'third_party/synth', 'sdk/include', 'app/synth', 'app']:
        flags += ['-I' + str(source / directory)]
    objects = []
    for index, file in enumerate(sources + [HERE / 'official_preview.c']):
        bc = out / f'{index:03}.bc'
        run(compiler, *flags, '-emit-llvm', '-Xclang', '-disable-llvm-passes', '-c', file, '-o', bc)
        objects.append(bc)
    run(linker, '-S', *objects, '-o', out / 'linked.ll')
    text = (out / 'linked.ll').read_text()
    # Internal names and exported APP functions are namespaced before archives
    # are linked together. External libc calls retain their platform ABI.
    names = set(re.findall(r'^define .*?@([\w.$]+)\(', text, re.M))
    names |= set(re.findall(r'^@([\w.$]+) = (?!external\b)', text, re.M))
    rename = {name: 'ofp_up_' + name for name in names if not name.startswith(('ofp_', 'llvm.', '.'))}
    text = re.sub(r'@([\w.$]+)', lambda match: '@' + rename.get(match[1], match[1]), text)
    (out / 'namespaced.ll').write_text(text)
    run(sys.executable, HERE / 'official_preview_state.py', out / 'namespaced.ll', out / 'state.ll', 'ofp_')
    run(compiler, '-target', triple, *tc.flags, '-O2', '-c', out / 'state.ll', '-o', out / 'official_preview.o')
    archive = out / 'libfm1_official_preview.a'
    run(*tc.ar, 'crs', archive, out / 'official_preview.o')
    record = {
        'schema_version': 1, 'preview_only': True, 'proprietary_sdk_linked': False,
        'source': LOCK['source'], 'commit': LOCK['commit'], 'release': LOCK['release'],
        'source_fingerprint': LOCK['browser_source_fingerprint'], 'target': triple,
        'compiler': version.strip(), 'compiler_path': str(compiler), 'flash_bytes': LOCK['flash_bytes'],
        'state_alignment': LOCK['state_alignment'], 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'adapter_sha256': {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest() for name in
            ['official_preview.c', 'official_preview_host.h', 'official_preview_build.py',
             'official_preview_state.py', 'official_preview_prepare.py', 'official_preview.lock.json', 'fel_state.py', 'target_config.py']},
    }
    (out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print('Built FM1 Open V14 PUBLIC SOURCE PREVIEW; no exact hardware firmware parity is claimed.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
