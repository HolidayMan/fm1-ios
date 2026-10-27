#!/usr/bin/env python3
"""Build and test exact CoralFlower native source on the Apple Silicon host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build as community_build
from coralflower_adapt import adapt


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--sanitize', action='store_true')
    a = p.parse_args()
    source, work = a.source.resolve(), a.work.resolve()
    d = json.loads((HERE / 'coralflower.lock.json').read_text())
    community_build.verify(source, d)
    repo = HERE.parents[2]
    for path in (source, work):
        if not path.is_relative_to(repo):
            raise SystemExit('Probe source/output must stay inside this private repository')
        run('git', '-C', repo, 'check-ignore', '-q', path)
    package = source.parent / d['package_filename']
    if package.stat().st_size != d['package']['size'] or hashlib.sha256(package.read_bytes()).hexdigest() != d['package']['sha256']:
        raise SystemExit('Exact release package fixture differs')
    upstream = work / 'upstream'
    if upstream.exists():
        shutil.rmtree(upstream)
    for part in d['copy_dirs']:
        shutil.copytree(source / part, upstream / part, ignore=shutil.ignore_patterns('.git', 'build', '__pycache__'))
    adapt(upstream)
    native = work / 'native'
    native.mkdir(exist_ok=True)
    shutil.copyfile(HERE / 'coralflower.c', native / 'coralflower.c')
    tc = community_build.Toolchain('aarch64-apple-darwin', 'macosx', llvm=True)
    flags = ['-target', tc.triple, *tc.flags, '-O2', '-std=gnu11', '-w', '-fwrapv', '-fno-strict-aliasing', '-ffp-contract=off']
    ll, ns, state = (work / n for n in ('core.ll', 'namespaced.ll', 'state.ll'))
    run(tc.cc, *flags, '-DFEL_PREFIX=cfl_', *tc.sections, '-I'+str(HERE.parent), '-I'+str(source/'build/gen'), '-I'+str(upstream/'firmware/src'),
        '-S', '-emit-llvm', '-Xclang', '-disable-llvm-passes', native/'coralflower.c', '-o', ll)
    ns.write_text(community_build.namespace_ir(ll.read_text(), 'cfl_'))
    run(sys.executable, HERE.parent/'fel_state.py', ns, state, 'cfl_')
    obj, lib, ref = (work / n for n in ('coralflower.o', 'coralflower.dylib', 'reference.dylib'))
    run(tc.cc, *flags, '-c', state, '-o', obj)
    run(tc.cc, *flags, '-dynamiclib', obj, '-o', lib)
    # Untouched upstream serial portable source, compiled to native machine code.
    # __EMSCRIPTEN__ selects its zero performance-counter fallback, without a
    # web compiler, web runtime, JS or a WASM binary.
    run(tc.cc, *flags, '-D__EMSCRIPTEN__', '-DEMU_WEB', '-DFELUCCA_VERSION="CoralFlower 0.5"',
        '-I'+str(source/'tools/emu/web/compat'), '-I'+str(source/'build/gen'), '-I'+str(source/'firmware/src'),
        '-dynamiclib', source/'tools/emu/web/emu_web.c', '-o', ref)
    run(sys.executable, HERE/'coralflower_test.py', '--library', lib, '--reference', ref, '-v')
    if a.sanitize:
        # Keep undefined-behavior frontend checks, then perform the same state
        # rewrite. Use the current Xcode sanitizer runtime on current macOS.
        checked = work/'sanitized.ll'
        rewritten = work/'sanitized-state.ll'
        sanitizers = ['-fsanitize=address,undefined', '-fno-sanitize-recover=all']
        run(tc.cc, *flags, *sanitizers, '-DFEL_PREFIX=cfl_', *tc.sections,
            '-I'+str(HERE.parent), '-I'+str(source/'build/gen'), '-I'+str(upstream/'firmware/src'),
            '-S', '-emit-llvm', '-Xclang', '-disable-llvm-passes', native/'coralflower.c', '-o', checked)
        checked.write_text(community_build.namespace_ir(checked.read_text(), 'cfl_'))
        run(sys.executable, HERE.parent/'fel_state.py', checked, rewritten, 'cfl_')
        run('xcrun', 'clang', '-O1', '-g', '-fwrapv', '-fno-strict-aliasing', '-ffp-contract=off',
            *sanitizers, rewritten, HERE/'coralflower_sanitize.c', '-o', work/'sanitizer-probe')
        env = dict(os.environ, ASAN_OPTIONS='detect_leaks=0', UBSAN_OPTIONS='print_stacktrace=1')
        subprocess.run([str(work/'sanitizer-probe')], cwd=work, env=env, check=True)
        run(sys.executable, HERE/'coralflower_compaction_test.py', '--reference', ref,
            '--before', work/'before.flash', '--after', work/'after.flash')


if __name__ == '__main__':
    main()
