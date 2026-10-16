# Local verification — 2026-10-16

## Passed

- Xcode 27.1: native iOS simulator app build (arm64), unsigned iOS device Release build (arm64). Device build is compilation, not installation.
- Rust release tests: 51 passed (34 CPU, 6 ISA, 9 SoC, 2 iOS boundary tests). No runtime third-party crates.
- iPhone simulator, iOS 27.0: two model tests and two UI tests. Panel controls F3/G5/HOME, firmware library, enlarged display, stock boot, C4 press/release, FX/HOME, pause/resume, and switching to Felucca.
- Offline binary smoke: both firmwares boot, keep CPU alive, draw a nonblank screen, produce nonzero stereo audio after a C4 matrix press and accept a flash round trip.
- Installed Virtual FM-1 version read: 0.9.1. App not changed.
- Software Factory repository remains clean; no queue/service invocation.

## Exact locally tested packages (not bundled or committed)

| Package | SHA-256 | Evidence |
|---|---|---|
| Manufacturer FM-1.fwsc, stored as Stock-V15 | db1642b2b6fa5c2cccb11ffd13878068bb28601678d3644049f99dc40e7edb8a | LCD and audio, matrix and transport/switch UI |
| Felucca 1.6.1 | dff3a38f7e5b9833e15aba322558c9485e9e422e3ff813c616c91b3584a2d909 | LCD and audio, boot/switch UI |

Fixtures were downloaded to ignored Research/Fixtures for local validation. Test copies were seeded into the dedicated simulator's private Documents/Firmwares directory. UI binary tests exercise selecting those copies; **Files picker import itself has not been tested end to end**. The importer is implemented and validation tested at the core boundary, but do not conflate that with file-provider acceptance.

## Performance and limits

The interpreter explicitly disables JIT. Under concurrent build/simulator activity, the offline test produced 10.34 seconds of stock audio in 10.60 wall seconds and 10.38 seconds of Felucca audio in 19.45 wall seconds. These are smoke/throughput observations on this Mac, not a controlled benchmark or iPhone performance result. Felucca can lag: real-time performance is an open blocker for product quality. Audio signal existence was measured; listening quality, latency, thermal behavior, chords at full polyphony and exact sound parity have not been accepted.

UI uses native Core Graphics with multi-touch tracking and matrix events, not a WebView. Small controls preserve the original proportions; physical-phone playability and VoiceOver need human checks. App currently pauses on foreground loss; it does not offer background audio. State snapshots are local and per imported filename/version. Checkpoint integrity, abrupt process termination and long recording sessions need further testing.

No factory `ready` status, separate reviewer approval, physical installation, TestFlight, App Review submission, App Store availability, or owner acceptance is claimed.
