# FM-1 for iOS — local prototype

Native landscape FM-1 panel (UIKit/Core Graphics + SwiftUI), with the real pi32v2 interpreter from **fm1-emu**. No web view, factory service, server, account, telemetry or downloaded runtime code.

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

1. Choose firmware → Import .fwsc from Files.
2. Select an FM-1 update package you obtained from its author. The app validates it before adding it to the private library and starts it.
3. Play chords on the 27 keys; drag knobs vertically; hold hardware buttons for firmware-specific combinations. Tap the LCD to enlarge it.
4. Pause/resume with the top transport; master controls the firmware's ADC. The speaker control is a separate output mute.
5. Each imported version has its own emulated flash. Saves inside the firmware persist; progress auto-checkpoints every five seconds, on firmware changes and on pause. Leaving the foreground pauses audio.

No firmware is distributed with the app. The stock update does not include the factory presets: upstream generates a small substitute bank. Do not describe this as the original 128 factory sounds or perfect hardware audio parity.

## Check

```sh
cargo test --workspace --release
xcodebuild -project FM1.xcodeproj -scheme FM1 -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR' -derivedDataPath build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
# Local files only, ignored by Git:
cargo run -p fm1-ios-core --release --example firmware_smoke -- /path/to/Firmware.fwsc
```

The smoke test runs the actual binary, presses/releases a note, checks a nonblank LCD and nonzero audio, round-trips flash and writes a WAV beside the input. It measures desktop interpreter throughput, not iPhone latency or listening quality.

See `docs/research.md` and `docs/verification.md` for evidence and remaining work. This is a local development prototype, not a Software Factory `ready` receipt or App Store release.
