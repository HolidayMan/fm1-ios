#!/usr/bin/env python3
"""Build and freeze an Apple core archive with verified local static kernels."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--kernels', type=Path, required=True)
p.add_argument('--target', choices=['aarch64-apple-ios-sim', 'aarch64-apple-ios', 'aarch64-apple-darwin'], required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--native-sloop', type=Path, help='Exact pinned SLOOP source prepared under ignored Research/')
a = p.parse_args()
header = a.kernels.resolve(strict=True)
subprocess.run(['python3', str(ROOT/'Vendor/fm1-core/tools/generate_static_kernels.py'), '--verify', str(header)], check=True)
manifest = json.loads(header.with_suffix('.manifest.json').read_text())
env = os.environ.copy()
env['FM1_STATIC_KERNELS'] = str(header)
if a.native_sloop:
    env['FM1_NATIVE_SLOOP'] = str(a.native_sloop.resolve(strict=True))
assert 'FM1_C_SANITIZE' not in env, 'Do not deliver a sanitizer-instrumented archive'
subprocess.run(['cargo', 'build', '--release', '-p', 'fm1-ios-core', '--target', a.target], cwd=ROOT, env=env, check=True)
target = Path(env.get('CARGO_TARGET_DIR', ROOT/'target'))
if not target.is_absolute():
    target = ROOT/target
archive = target/a.target/'release/libfm1_ios_core.a'
a.output.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(archive, a.output)
source_paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', 'Core', 'Vendor', 'Cargo.toml', 'Cargo.lock'], cwd=ROOT, text=True).splitlines()
source_hashes = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(set(source_paths))
                 if (ROOT/name).is_file() and (Path(name).suffix in {'.rs', '.c', '.h', '.def', '.toml', '.py'} or name=='Cargo.lock' or name=='Core/native/upstream.lock.json')}
receipt = {'archive': str(a.output.resolve()), 'archive_sha256': hashlib.sha256(a.output.read_bytes()).hexdigest(),
           'target': a.target, 'kernels': str(header), 'kernel_count': manifest['kernel_count'],
           'header_sha256': manifest['header_sha256'], 'generation_base_commit': manifest['source_commit'],
           'build_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'build_source_hashes': source_hashes,
           'source_hashes': manifest['sources'], 'firmware': manifest['firmware']}
if 'FM1_NATIVE_SLOOP' in env:
    native_source = Path(env['FM1_NATIVE_SLOOP']).resolve(strict=True)
    receipt['native_sloop'] = json.loads((ROOT/'Core/native/upstream.lock.json').read_text())
    receipt['native_sloop']['source_directory'] = str(native_source)
    receipt['native_sloop']['generated_hashes_verified_at_build'] = True
    receipt['native_sloop']['package_sha256'] = '7c9d269d15d1c1a48e0ebada7ffa2c2aa196c19d51056fd3f760d322322b335f'
a.output.with_suffix('.receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps(receipt, indent=2))
