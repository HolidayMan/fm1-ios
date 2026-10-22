#!/usr/bin/env python3
"""Fail a store build if research execution code/assets crossed its boundary.

Inspects the finished .app, not the working tree. Signing/distribution validation,
privacy answers, rights and physical acceptance remain separate release checks.
"""
import argparse
import plistlib
import re
import subprocess
import struct
from pathlib import Path

FORBIDDEN_SUFFIXES = {'.wasm', '.js', '.html', '.fwsc'}
FORBIDDEN_SYMBOLS = re.compile(r'WebInstrumentEngine|WebEngineOrigin|WebEngineHosting|WebEngineSurface|fm1_core|fm1_soc|fm1_isa|Interpreter')
NATIVE_POLICY = b'FM1_BUILD_POLICY_V1:NATIVE\0'
REQUIRED_REASONS = {
    'NSPrivacyAccessedAPICategoryUserDefaults': 'CA92.1',
    'NSPrivacyAccessedAPICategorySystemBootTime': '35F9.1',
}


def audit_resources(app):
    problems = []
    for resource in app.rglob('*'):
        if resource.is_file() and (resource.suffix.lower() in FORBIDDEN_SUFFIXES or 'WebEngine' in resource.parts):
            problems.append(f'Research/external package resource: {resource.relative_to(app)}')
    privacy = app / 'PrivacyInfo.xcprivacy'
    if not privacy.is_file():
        problems.append('PrivacyInfo.xcprivacy is missing')
    else:
        manifest = plistlib.loads(privacy.read_bytes())
        declared = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons']
                    for entry in manifest.get('NSPrivacyAccessedAPITypes', [])}
        for category, reason in REQUIRED_REASONS.items():
            if reason not in declared.get(category, []):
                problems.append(f'Missing required API reason: {category} / {reason}')
        if manifest.get('NSPrivacyTracking') is not False or manifest.get('NSPrivacyCollectedDataTypes') != []:
            problems.append('Privacy manifest differs from reviewed local-only data policy')
    return problems


def read_build_policy(executable):
    """Read the immutable policy section directly, including stripped arm64 apps."""
    data = executable.read_bytes()
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('Expected a thin 64-bit Mach-O executable')
    commands = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    for _ in range(commands):
        if offset + 8 > len(data):
            raise ValueError('Truncated Mach-O load commands')
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError('Invalid Mach-O load command size')
        if command == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise ValueError('Truncated Mach-O segment')
            sections = struct.unpack_from('<I', data, offset + 64)[0]
            if 72 + sections * 80 > size:
                raise ValueError('Truncated Mach-O sections')
            for index in range(sections):
                section = offset + 72 + index * 80
                name, segment = struct.unpack_from('<16s16s', data, section)
                if name.rstrip(b'\0') == b'__fm1_policy' and segment.rstrip(b'\0') == b'__TEXT':
                    length = struct.unpack_from('<Q', data, section + 40)[0]
                    start = struct.unpack_from('<I', data, section + 48)[0]
                    if length > 128 or start + length > len(data):
                        raise ValueError('Invalid build-policy section bounds')
                    return data[start:start + length]
        offset += size
    return None


def audit_binary(symbols, libraries, policy=None):
    problems = []
    found = sorted(set(FORBIDDEN_SYMBOLS.findall(symbols)))
    if found:
        problems.append('Research executable symbols: ' + ', '.join(found))
    if re.search(r'/(WebKit|JavaScriptCore)\.framework/', libraries):
        problems.append('Research framework dependency (WebKit/JavaScriptCore)')
    if policy != NATIVE_POLICY:
        problems.append('Signed native-only core build-policy section is missing or differs')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    app = args.app
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = app / info['CFBundleExecutable']
    symbols = subprocess.run(['xcrun', 'nm', '-a', str(executable)], check=True, text=True, capture_output=True).stdout
    libraries = subprocess.run(['xcrun', 'otool', '-L', str(executable)], check=True, text=True, capture_output=True).stdout
    problems = audit_resources(app) + audit_binary(symbols, libraries, read_build_policy(executable))
    if problems:
        raise SystemExit('\n'.join(problems))
    print('Store boundary passed: no research engine resources, symbols or frameworks; privacy manifest present.')


if __name__ == '__main__':
    main()
