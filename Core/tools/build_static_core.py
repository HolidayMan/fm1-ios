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
p.add_argument('--native-expansion', type=Path, help='Exact prepared FoMni/Jangada source root')
p.add_argument('--native-skiff', type=Path, help='Exact prepared Skiff source root')
p.add_argument('--native-family', type=Path, help='Exact prepared Felucca/X0X/Melodee source root')
p.add_argument('--native-official-preview', type=Path, help='Explicitly labelled official portable source preview')
p.add_argument('--native-sloop', type=Path, help='Exact pinned SLOOP source prepared under ignored Research/')
a = p.parse_args()
header = a.kernels.resolve(strict=True)
subprocess.run(['python3', str(ROOT/'Vendor/fm1-core/tools/generate_static_kernels.py'), '--verify', str(header)], check=True)
manifest = json.loads(header.with_suffix('.manifest.json').read_text())
env = os.environ.copy()
env['FM1_STATIC_KERNELS'] = str(header)
if a.native_sloop:
    env['FM1_NATIVE_SLOOP'] = str(a.native_sloop.resolve(strict=True))
if a.native_family:
    env['FM1_NATIVE_FAMILY'] = str(a.native_family.resolve(strict=True))
if a.native_official_preview:
    env['FM1_NATIVE_OFFICIAL_PREVIEW'] = str(a.native_official_preview.resolve(strict=True))
if a.native_expansion:
    env['FM1_NATIVE_EXPANSION'] = str(a.native_expansion.resolve(strict=True))
if a.native_skiff:
    env['FM1_NATIVE_SKIFF'] = str(a.native_skiff.resolve(strict=True))
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
                 if (ROOT/name).is_file() and (Path(name).suffix in {'.rs', '.c', '.h', '.def', '.toml', '.py'} or name=='Cargo.lock' or (name.startswith('Core/native/') and name.endswith('.json')))}
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
    receipt['native_sloop']['package_sha256'] = receipt['native_sloop']['sloop']['package']['sha256']
for variable, key, lock_file in [('FM1_NATIVE_FAMILY','native_family','family.lock.json'),
                                 ('FM1_NATIVE_OFFICIAL_PREVIEW','official_preview','official_preview.lock.json'),
                                 ('FM1_NATIVE_EXPANSION','native_expansion','expansion.lock.json'),
                                 ('FM1_NATIVE_SKIFF','native_skiff','skiff.lock.json')]:
    if variable in env:
        receipt[key] = json.loads((ROOT/'Core/native'/lock_file).read_text())
        receipt[key]['source_directory'] = str(Path(env[variable]).resolve(strict=True))
        receipt[key]['source_and_resource_hashes_verified_at_build'] = True
notices = [ROOT/'LICENSE', ROOT/'NOTICE'] + list((ROOT/'App').glob('NOTICE-native-*')) + list((ROOT/'App').glob('LICENSE-native-*')) + [file for file in (ROOT/'Core/native/licenses').rglob('*') if file.is_file()]
receipt['distribution_notices_sha256'] = {str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest() for file in sorted(notices) if file.is_file()}
a.output.with_suffix('.receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps(receipt, indent=2))
