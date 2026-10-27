#!/bin/sh
# Xcode builds its own matching core; Release cannot reuse a research archive.
set -eu
PATH="$HOME/.cargo/bin:$PATH"
export PATH
cd "$(dirname "$0")/.."
case "${PLATFORM_NAME:-}" in
    iphoneos) target=aarch64-apple-ios ;;
    iphonesimulator) target=aarch64-apple-ios-sim ;;
    *) echo 'FM1 core requires an iOS platform.' >&2; exit 2 ;;
esac
if [ "${CONFIGURATION:-}" = Release ]; then
    : "${FM1_NATIVE_SLOOP:?Prepare and explicitly select the pinned SLOOP source}"
    : "${FM1_NATIVE_FAMILY:?Prepare and explicitly select the pinned native family sources}"
    : "${FM1_NATIVE_SKIFF:?Prepare and explicitly select the pinned Skiff source}"
    : "${FM1_NATIVE_EXPANSION:?Prepare and explicitly select the pinned expansion sources}"
    : "${FM1_NATIVE_COMMUNITY:?Prepare and explicitly select the pinned community sources}"
    : "${FM1_NATIVE_OFFICIAL_PREVIEW:?Prepare and explicitly select the pinned official source}"
    CARGO_TARGET_DIR="$PWD/target/store" cargo build -p fm1-ios-core --lib --release --target "$target" --no-default-features --features store-native
else
    python3 scripts/verify_web_engine.py
    cargo build -p fm1-ios-core --lib --release --target "$target"
fi
