#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "${1:-simulator}" in
  simulator) target=aarch64-apple-ios-sim; sdk=iphonesimulator; destination='generic/platform=iOS Simulator' ;;
  device) target=aarch64-apple-ios; sdk=iphoneos; destination='generic/platform=iOS' ;;
  *) echo 'Usage: scripts/build.sh [simulator|device]' >&2; exit 2 ;;
esac
cargo build -p fm1-ios-core --release --target "$target"
python3 scripts/generate_project.py
xcodebuild -project FM1.xcodeproj -scheme FM1 -configuration Release -sdk "$sdk" -destination "$destination" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
