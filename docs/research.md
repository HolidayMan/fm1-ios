# FM-1 iOS research — 2026-10-16

## Decision

Implement a native panel and embed the MIT fm1-emu CPU/peripheral core behind a serial C ABI. Interpreter only, JIT explicitly off. Keep firmware packages user-supplied, stored privately, with independent flash snapshots. No factory tasks are submitted.

## Primary sources

- Manufacturer: https://www.sincoaudio.com/product?id=fm-1 — actual product photo, 27 keys, eight knobs including MASTER, two octave buttons, twelve function buttons, central color display. Reference photograph: https://www.sincoaudio.com/images/productInfo/fm-1-1.webp . Our panel uses SEL (the photograph) even though the upstream panel diagram labels it SCL.
- CPU emulator: https://github.com/joakimeriksson/fm1-emu — MIT, native Rust, actual JieLi AC791N/pi32v2 CPU and peripherals, dual-core execution, .fwsc parsing, LCD, matrix, audio and flash. Pinned revision in Vendor/UPSTREAM.md. Upstream reports dozens of firmware versions; that is upstream coverage, not our iOS validation.
- Virtual FM-1: https://github.com/jbschooley/Virtual-FM-1 — source-built engine/plugin architecture, not a generic arbitrary-binary CPU emulator. Its README documents approximation/gaps, source-built community engines, and iOS/AUv3 source targets. GPL/AGPL/JUCE licensing and individual sound assets make it a different product basis. The installed Mac app reports version 0.9.1; it was not modified.
- Firmware discovery: https://fm1-editor.com/firmware/ and https://thefirmwarehub.com/ . Catalogs are discovery material, not proof every binary is compatible or redistributable. Read each author's license and release notes.
- Apple: https://developer.apple.com/app-store/review/guidelines/ — 2.5.2 limits code that changes app functionality, 4.7 describes specific software/plugin/emulator exceptions, 5.2 covers third-party rights. A synthesizer firmware loader is not explicitly guaranteed by the game-emulator exception. This is an unresolved App Review question, not an assertion of rejection or acceptance.

## Compatibility definition

A .fwsc extension alone proves nothing. A version needs package validation, successful boot, functioning display and controls, audible note-on/off, correct clock/audio rate, saves surviving restart and acceptable performance on the minimum supported physical device. The prototype accepts valid FM-1 packages up to 4 MiB; SMK-37 packages are rejected. File parsing and execution are panic-contained; this is not a completed untrusted-firmware security audit.

The stock update omits the unit's original preset area. The emulator supplies its own small patch bank. We must add licensed/user-owned DX7 bank import before claiming original preset parity. Host sample-rate conversion uses AVAudioEngine from the firmware's 44.1 kHz stream.

## Before App Store

1. Validate interpreter performance/thermal behavior/latency on the actual minimum iPhone and iPad; optimize the slow cases without relying on JIT entitlements.
2. Establish an explicit supported-version matrix and regression audio/control fixtures; improve unsupported/hung-firmware diagnosis.
3. Decide distribution rights and App Review route for user-supplied binary firmware. Alternative if necessary: approved engines included in each signed release. Do not silently replace the requested generic loader with that alternative.
4. Physical sound comparison, original-bank import, CoreMIDI and later AUv3, session restoration, resilient background checkpointing, accessibility and small-screen playing ergonomics.
5. Final independent product name/branding, icon, metadata/privacy/support URLs, App Review notes, signing and TestFlight. No submission has occurred.
