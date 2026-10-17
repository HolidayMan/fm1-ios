# FM-1 for iOS

Native adaptive landscape FM-1 panel (UIKit/Core Graphics + SwiftUI), with a hybrid audio engine: exact pinned SLOOP 2.7.1 can use compiled firmware source, while other packages use the pi32v2 interpreter from **fm1-emu**. No web view, factory service, account or telemetry. Downloaded packages cannot generate or modify executable host code.

Unofficial iOS prototype for M-VAVE FM-1. Not affiliated with M-VAVE. Tested locally on iPhone 12; not an App Store release.

![FM-1 interface](docs/screenshots/fm1-iphone12-blackgreen-v2.png)

Screenshots document earlier development builds; current palettes were corrected against manufacturer photographs. See [finish references](docs/panel-finishes.md).

## Build

Xcode, Rust, Python 3 (project and optional static-kernel generation). No Swift packages or external Rust crates.

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build.sh simulator
# Unsigned arm64 device build:
./scripts/build.sh device
```

Open `FM1.xcodeproj`; choose your own signing team for a physical device. Build the Rust target first. Current simulator library supports Apple Silicon.

The commands above build the generic interpreter. An optimized local build additionally requires private generated kernels and their verified manifest; set `FM1_STATIC_KERNELS` to the absolute header path when building Rust. `Core/tools/build_static_core.py` verifies those inputs and freezes a target-specific archive with a source/hash receipt. The generator is in `Vendor/fm1-core/tools/generate_static_kernels.py`; firmware-derived inputs and outputs remain local under ignored `Research/Generated`. No runtime JIT is used.

A local hybrid build can additionally compile exact SLOOP 2.7.1 source for its
pinned package, with the binary interpreter retained for every unmatched package.
For the fast pinned SLOOP backend (build-only Pillow dependency):

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install Pillow
python3 Core/native/prepare.py "$PWD/Research/NativeSloop/upstream-sloop-2.7.1"
FM1_NATIVE_SLOOP="$PWD/Research/NativeSloop/upstream-sloop-2.7.1" ./scripts/build.sh simulator
# Use the same environment variable with ./scripts/build.sh device for iPhone.
```

This native backend does not require the optional private static-kernel captures.
Other firmware remains interpreted and can exceed the real-time budget.

This addresses the recorded-sequencer CPU bottleneck. The source-native backend
has GPL-3.0 notices and a different hardware/main-loop model; see
[docs/native-sloop.md](docs/native-sloop.md) for build pins, save compatibility,
measurements and limits. No runtime JIT is used.

## Play

1. Choose firmware → pick one of 53 pinned catalogue releases, or Import .fwsc from Files.
2. Catalogue downloads are checked against their recorded size and SHA-256, then validated by the core before entering the private library. Import remains available for other releases.
3. Play chords on the 27 keys; drag knobs vertically; hold hardware buttons for firmware-specific combinations. Tap the LCD to enlarge it.
4. The remembered/default installed firmware starts automatically on app launch. Pause/resume with the top transport; an explicit pause survives background/foreground transitions within the running app. Master controls the firmware's ADC. The speaker control is a separate output mute.
5. Each imported version has its own emulated flash. Saves inside the firmware persist; progress auto-checkpoints every five seconds, on firmware changes and on pause. Leaving the foreground temporarily pauses audio; returning resumes it unless explicitly paused. System interruptions and removed audio outputs retain their own resume rules.

The signed app includes catalogue metadata, not firmware binaries. It downloads selected releases on demand from M-VAVE and FM-1 Firmware Hub. The snapshot covers 52 Hub releases plus Stock V15; it is not an exhaustive claim about every firmware on the internet. The stock update does not include the factory presets: upstream generates a small substitute bank. Do not describe this as the original 128 factory sounds or perfect hardware audio parity.

## Check

```sh
cargo test --workspace --release
xcodebuild -project FM1.xcodeproj -scheme FM1 -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR' -derivedDataPath build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
# Local files only, ignored by Git:
cargo run -p fm1-ios-core --release --example firmware_smoke -- /path/to/Firmware.fwsc
```

The smoke test runs the actual binary, presses/releases a note, checks a nonblank LCD and nonzero audio, round-trips flash and writes a WAV beside the input. It measures desktop interpreter throughput, not iPhone latency or listening quality.

Choose Panel color for the six manufacturer finishes; the choice persists. The native touch layout uses the available screen area instead of fixed physical proportions.

The generic interpreter exceeds the real-time CPU budget for Felucca and SLOOP. Optional build-time specializations substantially reduce that cost while retaining exact interpreter fallback for other code. See `docs/performance-next-step.md` for the architecture and `docs/performance-lab.md` for controlled simulator measurements; simulator timing is not physical iPhone timing.

See `docs/research.md` and `docs/verification.md` for evidence and remaining work. This is a local development prototype, not a Software Factory `ready` receipt or App Store release.

## License and attribution

This project is distributed under GPL-3.0-only; see [LICENSE](LICENSE). The source-native wrapper and state tooling derive from Virtual FM-1, and the pinned SLOOP firmware is GPL-3.0-only. The vendored fm1-emu interpreter retains its MIT license. Individual upstream components retain their original licenses and notices; see [NOTICE](NOTICE), [interpreter provenance](Vendor/UPSTREAM.md) and [native-backend attribution](App/NOTICE-native-sloop).

No firmware binaries, factory sound banks, private saved projects, generated kernels, device builds or signing credentials are included. Public upstream source/resources are fetched by the opt-in native preparation step. Firmware and third-party asset rights remain with their authors. Publishing this source does not establish App Store approval or grant rights to redistribute arbitrary firmware.
