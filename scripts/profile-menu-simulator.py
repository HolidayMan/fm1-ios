#!/usr/bin/env python3
"""Run opt-in menu/frame profiling against an isolated local SLOOP library.

Build the desired native simulator archive first. This does not build Rust, touch
phone data, download firmware, or run an app in another project. Reports and full
logs stay in ignored Research/ and build/ directories.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
SIMULATOR='CAF633C4-871C-42EA-B179-3C33DCE401E4'
BUNDLE='com.local.fm1.instrument'

def run(command,log=None):
    if log:
        with log.open('w') as output:
            subprocess.run(command,cwd=ROOT,stdout=output,stderr=subprocess.STDOUT,check=True)
    else:
        return subprocess.check_output(command,cwd=ROOT,text=True).strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--project',type=Path,default=ROOT/'FM1.xcodeproj')
    parser.add_argument('--derived-data',type=Path,required=True)
    parser.add_argument('--simulator',default=SIMULATOR)
    parser.add_argument('--mode',choices=['native','wasm'],default='native')
    parser.add_argument('--reuse-build',action='store_true')
    args=parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]{1,48}',args.label):parser.error('Use a short alphanumeric/hyphen label')
    package=args.package.resolve()
    if not package.is_file() or package.suffix.lower()!='.fwsc':parser.error('Requires an existing local .fwsc package')
    expected=next(entry['sha256'] for entry in json.loads((ROOT/'App/FirmwareCatalog.json').read_text()) if entry['id']=='sloop')
    if hashlib.sha256(package.read_bytes()).hexdigest()!=expected:parser.error('The menu profile requires the exact pinned SLOOP package')
    project=args.project.resolve();derived=args.derived_data.resolve()
    reports=ROOT/'Research/MenuProfile';reports.mkdir(parents=True,exist_ok=True)
    destination=f'platform=iOS Simulator,id={args.simulator}'
    if not args.reuse_build:
        print(f'Building profiling app: {args.label}',flush=True)
        run(['xcodebuild','-project',str(project),'-scheme','FM1','-configuration','Release',
             '-destination',destination,'-derivedDataPath',str(derived),'-parallel-testing-enabled','NO',
             'CODE_SIGNING_ALLOWED=NO','ENABLE_TESTABILITY=YES','DEBUG_INFORMATION_FORMAT=dwarf-with-dsym','-only-testing:FM1UITests/MenuResponsivenessUITests',
             'build-for-testing'],reports/f'{args.label}-build.log')
    app=derived/'Build/Products/Release-iphonesimulator/FM1.app'
    run(['xcrun','simctl','install',args.simulator,str(app)])
    container=Path(run(['xcrun','simctl','get_app_container',args.simulator,BUNDLE,'data']))
    relative=Path('Documents/PerformanceFixtures')/f'menu-profile-{args.label}'
    fixture=container/relative
    if fixture.exists():raise RuntimeError('Profile fixture already exists; choose a fresh label')
    fixture.mkdir(parents=True)
    shutil.copy2(package,fixture/'SLOOP-2.7.1.fwsc')
    specs=list((derived/'Build/Products').glob('FM1_*.xctestrun'))
    if len(specs)!=1:raise RuntimeError('Expected one generated FM1 xctestrun')
    spec=plistlib.loads(specs[0].read_bytes())
    spec['FM1UITests'].setdefault('EnvironmentVariables',{}).update({
        'FM1_PROFILE_MENUS':'1','FM1_PROFILE_MODE':args.mode,
        'FM1_APP_LIFECYCLE_FIXTURE_DIRECTORY':str(relative)})
    active=specs[0].with_name(f'MenuProfile-{args.label}.xctestrun');active.write_bytes(plistlib.dumps(spec))
    result=derived/f'{args.label}.xcresult'
    began=time.time()
    print(f'Running real menu interactions: {args.label}',flush=True)
    run(['xcodebuild','test-without-building','-xctestrun',str(active),'-destination',destination,
         '-parallel-testing-enabled','NO','-only-testing:FM1UITests/MenuResponsivenessUITests',
         '-resultBundlePath',str(result)],reports/f'{args.label}-test.log')
    container=Path(run(['xcrun','simctl','get_app_container',args.simulator,BUNDLE,'data']))
    source=container/'Documents/PerformanceReports/menu-responsiveness.json'
    if not source.is_file() or source.stat().st_mtime<began:raise RuntimeError('No fresh frame report was written')
    report=reports/f'{args.label}.json';shutil.copy2(source,report)
    print(json.dumps(json.loads(report.read_text()),indent=2))
    print(f'Report: {report}\nUI result: {result}',flush=True)

if __name__=='__main__':main()
