# Local verification

## Historical baseline — 2026-10-16

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

The baseline UI used native Core Graphics with multi-touch tracking and matrix events, not a WebView. Its small controls preserved physical proportions; this has been replaced by the adaptive layout below. Physical-phone playability and VoiceOver need human checks. App currently pauses on foreground loss; it does not offer background audio. State snapshots are local and per imported filename/version. Checkpoint integrity, abrupt process termination and long recording sessions need further testing.

No factory `ready` status, separate reviewer approval, physical installation, TestFlight, App Review submission, App Store availability, or owner acceptance is claimed.

## Native touch revision — 2026-10-17

- Adaptive screen-point layout fills the landscape safe width, with a compact transport and no footer. Knobs and function buttons are larger; hardware control groups and multitouch remain.
- Six manufacturer finish choices in an all-visible two-column grid, persisted across launch. Colors approximate the published product selector.
- 53 pinned catalogue releases (52 Hub + Stock): all download URLs fetched, size/SHA-256 verified, all packages accepted by instrument_create. This is format validation, not a 53-firmware boot/audio certification.
- Physical installation of baseline 0.1.0 (1) on paired iPhone12 was verified on 2026-10-16 over localNetwork, with Stock and Felucca seeded into its private Documents. User subsequently reported small controls and audio artifacts, which motivated this revision.
- Current revision checks and performance results are recorded below when complete.

### UI and host audio checks

- Dedicated iPhone12 simulator, iOS27.0, CAF633C4-871C-42EA-B179-3C33DCE401E4. Six model/catalogue/audio tests passed; the physical-device-only test was skipped on simulator. Four UI scenarios passed across r4/r5/r6 results: hardware/library/display, local firmware playback and switching, actual catalogue downloads with selected-version confirmation, and control geometry/color persistence. Earlier failed runs exposed test fixture/search visibility assumptions; these were fixed and rerun. UI suite used the original simulator Rust archive; final Rust behavior is checked separately.
- Native screenshot review: Stock, Felucca, White-Blue, Black-Green in docs/screenshots/*iphone12*-v2.png. Function buttons meet tested 44×40pt bounds, knobs ≥44pt, piano key width≥40pt; keyboard fills >83% of whole screen width and extends to the bottom. Six colors visible together in landscape.
- The first safe checkpoint used four reusable512-frame player buffers. The current audio path replaces completion-driven refill with AVAudioSourceNode and a C11 single-producer/single-consumer ring:34.8ms target/46.4ms capacity. The worker yields between512-frame production chunks; the callback copies/de-clicks samples and signals a coalesced refill. No interpreter runs in the callback. C sample rendering has no allocation or locks; DispatchSource wakeup has no claimed hard-real-time guarantee. Snapshot hash/disk I/O runs on a serial storage queue; switching waits outstanding saves and pause requests bounded background time for a durable checkpoint.
- Current diagnostics distinguish core missing frames, render-time ratio and actual ring-output underflow frames/callbacks, with delivered/requested output totals. Legacy estimated player-queue gap fields remain for report compatibility and are zero in source-ring reports. Ring underflows are not OS/device deadline counters or listening acceptance. Complete firmware audio buffers pass unchanged; unavailable audio/recovery receives a short fade.

### Physical safe-checkpoint measurement

On the paired iPhone12/iOS26.6.2, optimized Release build, 25-second sustained-note scenarios, safe checkpoint before the experimental XIP trace optimization:

| Firmware | Mean render budget used | Recent p95 | Missing core frames | Estimated queue gaps |
|---|---:|---:|---:|---:|
| Stock V15 | 50.4% | 58.4% | 0 | 3 /104ms total |
| Felucca1.6.1 | 131.0% | 145.8% | 3072 | 888 /3.87s total |
| SLOOP2.7.1 | 120.1% | 136.5% | 3072 | 1548 /4.85s total |

Physical test completed successfully as a measurement harness, **not** as a real-time quality gate. Felucca did not meet real time; Stock had measured outliers. Hardware output48kHz, engine input44.1kHz, requested I/O10ms. Firmware flash state was preserved. Private detailed reports live under ignored Research/Performance/. No claim of pop-free listening or full-polyphony performance follows from this test.

SLOOP was measured in a separate25-second run after the user reported the same issue; its existing downloaded package and flash were preserved. The test now prevents idle screen locking during the measurement; the first Stock/Felucca baseline lacked that guard, so elapsed/duty-cycle comparisons from those earlier runs have that limitation.

### Audio ring validation

- C11 warnings-as-errors passed. Concurrent ThreadSanitizer stress:2,097,152 stereo frames over16 producer/consumer runs, exact left/right sequence through wraps and final frame conservation; no race diagnostics.
- Reproduce from repository root: `clang -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=thread App/AudioRing.c Tests/AudioRingStress.c -o /tmp/fm1-audio-ring-stress && /tmp/fm1-audio-ring-stress`.
- Swift host assertions and physical-device XCTest ring tests passed for bounds, wrap, underflow smoothing/recovery across callbacks and counters. Independent review found no concrete SPSC ownership, generation or memory-lifetime blocker.

### Final retained core and source-ring measurements

- Final Rust workspace:55 release tests pass. Original versus retained implementation matches PCM, LCD and flash fingerprints for Stock V15, Felucca1.6.1 and SLOOP2.7.1. Same-Mac measured wall times: Stock4.17→3.83s, Felucca11.14→10.46s, SLOOP10.70→9.97s (6–8% lower time in this run; not an iPhone speed claim). Experimental trace/scan/static-handler/layout changes were removed when they failed to beat the smaller retained implementation consistently.
- Physical Release XCTest run with the source ring:12 tests passed, including three25-second firmware measurements with idle locking disabled. This run used the retained safe core before final metadata cache bounds/describe changes and before the final import-identity/About UI edits.

| Firmware | Mean render budget | Recent p95 | Actual output missing/requested | Missing output share |
|---|---:|---:|---:|---:|
| Stock V15 | 47.7% | 64.0% | 714 /1,144,395 | 0.062% |
| Felucca1.6.1 | 130.6% | 138.1% | 276,383 /1,139,985 | 24.24% |
| SLOOP2.7.1 | 121.5% | 129.8% | 223,748 /1,145,277 | 19.54% |

These are actual ring sample shortages, not perceived dropout duration or OS audio deadline measurements. **Felucca and SLOOP still fail real time on iPhone12.** Stock also had a small shortage; no crackle-free listening acceptance is claimed. The next architecture experiment and acceptance criteria are documented in performance-next-step.md.

### Local device delivery

Final clean Release app0.2.0(2), bundle com.local.fm1.instrument, built in build-device/Delivery; strict deep code-signature verification passed. Installed over the paired local connection and successfully launched on the owner's iPhone12. Installed-app inventory confirms version/build. Post-install file inventory confirms all three existing firmware packages and their corresponding flash files remain. No uninstall, TestFlight upload, external publication or App Review submission occurred. Delivery receipts are private under ignored build-device/.

### Final simulator integration

Rebuilt the final Rust Release simulator archive and ran current native app tests on the dedicated iPhone12/iOS27.0 simulator:10 model/audio/import tests passed,3 physical-only tests skipped, and the playback/firmware-switch UI smoke passed. The reimport test confirmed exact original selected ID, unchanged installed-ID set, byte-identical existing flash file immediately after reimport, and staging cleanup. This is importer integration coverage, not an end-to-end Files-provider test or full patch-state playback verification. Result: build-final-simulator/Final-validation.xcresult (ignored). Independent reviewers found no blocking issue in the retained core, audio ring or import identity change.
