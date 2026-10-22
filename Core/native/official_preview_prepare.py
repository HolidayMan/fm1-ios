#!/usr/bin/env python3
"""Prepare pinned public FM1 Open preview sources in an ignored local directory."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LOCK = json.loads((HERE / 'official_preview.lock.json').read_text())


def ignored_path(path):
    path = Path(path).resolve()
    if not path.is_relative_to(REPO) or path == REPO:
        raise ValueError('Native preview inputs/outputs must stay inside this repository and be ignored.')
    if subprocess.run(['git', '-C', str(REPO), 'check-ignore', '-q', str(path)]).returncode:
        raise ValueError('Native preview inputs/outputs must be Git-ignored: ' + str(path))
    return path


def verify(source):
    source = ignored_path(source)
    head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if head != LOCK['commit']:
        raise ValueError('FM1 Open preview requires exact source commit ' + LOCK['commit'])
    subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', 'HEAD'], check=True)
    actual = {}
    for directory in LOCK['compiled_source_directories']:
        for file in (source / directory).rglob('*'):
            name = file.relative_to(source).as_posix()
            if file.is_file() and file.suffix in ('.c', '.h', '.inc') and not name.startswith('app/board/'):
                actual[name] = hashlib.sha256(file.read_bytes()).hexdigest()
    for file in [source / 'tools/Build-Web.ps1', *(source / 'sdk/include').glob('*.h')]:
        actual[file.relative_to(source).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    if actual != LOCK['inputs']:
        raise ValueError('Pinned FM1 Open browser sources differ, including missing/extra local inputs.')
    for name, expected in LOCK['notices_sha256'].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise ValueError('FM1 Open notice differs: ' + name)
    digest = hashlib.sha256('\n'.join(name + ':' + actual[name] for name in sorted(actual)).encode()).hexdigest()
    if digest != LOCK['browser_source_fingerprint']:
        raise ValueError('FM1 Open browser source fingerprint differs from the official workbench.')
    return source


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source', type=Path)
    p.add_argument('--verify-only', action='store_true')
    args = p.parse_args()
    source = ignored_path(args.source)
    if not source.exists():
        if args.verify_only:
            sys.exit('Pinned FM1 Open source directory is missing.')
        source.parent.mkdir(parents=True, exist_ok=True)
        # Only a new checkout is touched. Existing checkouts are never reset.
        subprocess.run(['git', 'clone', '--depth', '1', LOCK['source'], str(source)], check=True)
        head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
        if head != LOCK['commit']:
            subprocess.run(['git', '-C', str(source), 'fetch', '--depth', '1', 'origin', LOCK['commit']], check=True)
            subprocess.run(['git', '-C', str(source), 'checkout', '--detach', LOCK['commit']], check=True)
    verify(source)
    print('Verified exact FM1 Open V14 PUBLIC PREVIEW source; no proprietary SDK is linked: ' + str(source))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
