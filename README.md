# FM-1 for iOS — local prototype

Native adaptive landscape FM-1 panel (UIKit/Core Graphics + SwiftUI), with the real pi32v2 interpreter from **fm1-emu**. No web view, factory service, account or telemetry. Firmware downloads are interpreted only inside the emulated synthesizer.

This project is developed directly in the Software Factory project context. **The Software Factory queue is not used or changed.**

## Build

Xcode, Rust stable, Python 3 (project generation only). No Swift packages or external Rust crates.

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build.sh simulator
# Unsigned arm64 device build:
./scripts/build.sh device
```

Open `FM1.xcodeproj`; choose your own signing team for a physical device. Build the Rust target first. Current simulator library supports Apple Silicon.

## Play

1. Choose firmware → pick one of 53 pinned catalogue releases, or Import .fwsc from Files.
2. Catalogue downloads are checked against their recorded size and SHA-256, then validated by the core before entering the private library. Import remains available for other releases.
3. Play chords on the 27 keys; drag knobs vertically; hold hardware buttons for firmware-specific combinations. Tap the LCD to enlarge it.
4. Pause/resume with the top transport; master controls the firmware's ADC. The speaker control is a separate output mute.
5. Each imported version has its own emulated flash. Saves inside the firmware persist; progress auto-checkpoints every five seconds, on firmware changes and on pause. Leaving the foreground pauses audio.

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

Felucca and SLOOP still exceed the real-time CPU budget on the tested iPhone12; the new audio ring does not eliminate this interpreter limit. See `docs/performance-next-step.md` for the measured bottleneck and next experiment.

See `docs/research.md` and `docs/verification.md` for evidence and remaining work. This is a local development prototype, not a Software Factory `ready` receipt or App Store release.
