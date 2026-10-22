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


## Static hot-block optimization — intermediate build 3, 2026-10-17

Candidate app 0.2.1 (3) uses 768 build-time kernels guarded by exact decoded-block equality, with reference fallback. No runtime JIT, guest-clock reduction or synthesis approximation. Generated firmware-derived code remains local/ignored. Independent core review found no remaining blocker at generated-header SHA-256 `1be5505c7ec9fb5e65e3878518eb6e8f392194b13f02211cd5a33a53e083d505`.

- Paired host ABBA against the frozen `70b25ce` executable (two runs per implementation, alternating firmware order): Felucca 10.5526→5.4700 seconds (48.16% less time), SLOOP 10.0754→5.5750 (44.67% less), Stock 3.7558→3.8550 (2.64% more). All PCM/LCD/flash fingerprints match in every run. This is Mac throughput, not phone latency.
- 61 Rust workspace Release tests passed; six focused suites include all 768 generated kernels across 96 states, descriptor mutation rejection, entry budgets/prefixes, code-write/MMIO fallback, panic containment and ABI offsets. All six also passed C AddressSanitizer and UndefinedBehaviorSanitizer checks with halt-on-error.
- The dedicated iPhone 12 / iOS 27.0 simulator reproduced the baseline CPU bottleneck. Three 25-second comparisons, three 60-second steady audio stress cases and eight ordinary audio/ring/window tests passed. Exact firmware and initial flash snapshots were checked; prior simulator package/save bytes were restored and verified after XCTest relocated its data container. See `performance-lab.md` for complete methodology and receipts.
- Simulator steady stress means: Stock 67.23%, Felucca 58.91%, SLOOP 60.27%; zero additional missing core frames or output samples in every measured phase. Stock's three-key phase recent p95 was 99.04%, so its stress headroom remains small. Warmup is separate: Stock had 512 output samples missing during warmup; Felucca/SLOOP each retain their known 3,072 initial core-missing frames.
- Stock's startup-inclusive simulator mean increased from 47.36% to 56.86%, despite a comparable recent p95 (52.76% to 52.40%); this result is retained rather than dismissed. There is no baseline with the new repeated-attack stress scenario, so its load cannot be attributed to the optimization alone.

### Physical iPhone 12, same retained owner saves

Release test bundle built from the candidate kernel archive; iPhone13,2, iOS 26.6.2, hardware output 48 kHz / firmware source 44.1 kHz. Three original 25-second scenarios passed as measurements. Low-power mode was off and reported thermal state nominal. Firmware packages and existing saves were retained; unlike the controlled simulator, owner saves were not reset to baseline fixtures.

| Firmware | Previous mean | Candidate mean / recent p95 | Candidate missing / requested output samples |
|---|---:|---:|---:|
| Stock V15 | 47.67% | 52.44% / 62.94% | 714 / 1,144,395 (0.0624%) |
| Felucca 1.6.1 | 130.56% | 57.94% / 63.05% | 191 / 1,139,985 (0.0168%) |
| SLOOP 2.7.1 | 121.50% | 59.29% / 62.90% | 15 / 1,144,836 (0.0013%) |

These totals include startup and do not locate each shortage in time. The subsequent sustained physical-device run passed all three cases: Felucca mean 58.42% / recent p95 64.28%, SLOOP 60.84% / 64.45%, Stock 69.47% / 101.70%. All steady phases had zero additional core/output shortages. Stock's last-phase recent p95 exceeded budget despite zero shortages, which motivated the final RAM fallback change below. No listening, full-polyphony, long-session thermal or all-firmware acceptance follows from these short tests. Private reports: `Research/Performance/physical-aot-build3`; result bundle: `build-device/Performance-AOT/Physical.xcresult`.


## Final RAM fallback revision — app 0.2.1 (4)

Only XIP code enters the C/static-kernel backend. RAM-resident code retains the original Rust path, avoiding unnecessary partial-exit/FFI overhead in Stock's second CPU. An isolated alternating Stock comparison improved 3.87/3.93 seconds to 3.58/3.58 (about 8%); a subsequent three-firmware smoke retained exact PCM/LCD/flash fingerprints with no Felucca/SLOOP slowdown. The generated kernel content is unchanged; the source manifest was regenerated for the guard.

All 62 Rust workspace Release tests passed both with and without generated kernels. Seven focused suites passed ASan/UBSan, including a new test that RAM fallback changes neither state nor ticks. Independent review found no blocker in the guard or updated build receipt. The build-3 measurements above are intermediate evidence, not mislabeled as build-4 measurements.


Final physical iPhone 12 stress: all three 65-second cases passed (5 seconds warmup, 60 seconds measured). Every single-key, three-key and three-key-plus-encoder phase had zero additional core-missing or output-underrun samples/callbacks, approximately 100% output-clock coverage, 20 retriggers per phase and 160 encoder events. Mean / recent p95 at the end:

| Firmware | Physical mean | Physical recent p95 | Steady output/core shortages |
|---|---:|---:|---:|
| Stock V15 | 58.75% | 93.09% | 0 / 0 |
| Felucca 1.6.1 | 58.18% | 63.50% | 0 / 0 |
| SLOOP 2.7.1 | 60.71% | 63.75% | 0 / 0 |

Stock's phase means were 54.15%, 60.52% and 61.59%; recent p95 values 77.24%, 82.65% and 93.09%. This improves its intermediate same-device stress, but the last phase still has less margin than the other firmware. The recent p95 is a trailing 256-render window, not a full-phase percentile. These tests establish sample availability for these exact patches/input workloads; listening, long thermal sessions, all catalogue releases and full-polyphony acceptance remain separate.

Private final reports: `Research/Performance/physical-aot-final-build4`; `build-device/Performance-AOT/FinalPhysicalStress.xcresult`. Simulator archive SHA-256: `7a54c09eeb1e3ddd47b74fa058aca0c4a482bf21d2d44618f2ef99e0ee203cfd`; device archive: `bd7c090007f0014e780fb1ccf69b7b7cf06b8ba635a85cda08e45bdc630ddb30`. Full source/hash receipts accompany both. Durable private core comparison/test logs are in `Research/Performance/final-core-validation`.


Final simulator stress also passed all three cases: Stock mean 57.96% / recent p95 85.16%, Felucca 58.62% / 62.58%, SLOOP 59.66% / 63.16%. Every measured phase had zero additional core/output shortages; each firmware delivered all 2,646,528 requested steady output samples. The simulator was shut down and its prior package/save bytes restored. Final runner: `Research/Performance/aot-final-stress-4`; full details in `performance-lab.md`.

### Final local delivery

Clean signed Release app 0.2.1 (4) passed strict deep code-signature verification, installed over the paired connection and launched successfully on the owner's iPhone 12. Installed-app inventory confirms version/build; file inventory confirms Stock, Felucca and SLOOP packages and all three corresponding flash files remain. No uninstall, TestFlight, publication or App Review submission. Private install/launch/app/file receipts and signed executable hash are under `build-device/aot-final-*`. Owner listening acceptance is still required; this report does not call the app crackle-free across all patches or conditions.


Final physical warmup counters remain explicit: output shortages were Stock 273, Felucca 191 and SLOOP 0 samples; Felucca/SLOOP also report 3,072 initial core-missing frames each. They are excluded from the stated steady gates, not erased or treated as a zero-startup result. Low-power mode remained off; final Stock thermal state was fair (1), with Felucca/SLOOP nominal (0). No sustained thermal acceptance is claimed.


## Native SLOOP 2.7.1 and recorded-loop regression — 0.3.0 (5)

The user's recorded drum loop exposed an untested workload: prior three-key stress was not a sequencer test. A read-only physical diagnostic showed 106.8% mean render budget and 6.61% missing output samples. Offline reproduction from confirmed saved flash isolated increased CPU1/voice workload with nominal guest-clock progression. See `native-sloop.md` for the cause, exact source pins, hybrid design and compatibility limits.

The exact SLOOP 2.7.1 package now selects source-native execution; unmatched firmware retains the interpreter. Native source/resource provenance is pinned and generated-header corruption/missing-input guards were independently checked. 68 native Rust tests and 63 interpreter-only tests passed, including all four user-sample slots, full flash persistence, FIFO chunking, independent instances, master smoothing and record/save/reopen. 182 upstream DSP goldens were unchanged; this is not a claim of complete application PCM/boot/input-timing parity.

Keyboard hit testing now covers the small dead gutters/bottom strip while preserving drawn-control priority and multitouch ownership. This historical build restored the remembered firmware paused (superseded by the lifecycle revision below); absent a remembered installed choice, it prefers installed SLOOP 2.7.1 or the newest installed SLOOP release. No automatic download occurs. Six initial targeted geometry/selection tests and 16 final focused Swift tests passed, including optional backend diagnostics and bundled license notices. A separate independent review found no actionable UI issue.

### Simulator integration

Final frozen simulator core SHA-256 `0e40e9280c0904f57a8ceb3f5fd5aaf00753b856be0304e48d5e6749515fcc72`, native app 0.3.0 (5), dedicated iPhone 12 simulator. Each case uses an isolated local fixture directory and verified flash hash; the runner restores prior Documents and Preferences byte-for-byte and shuts the simulator down.

The owner-loop case passed 30 seconds of playback, with rapid repeated kick-pad input for the final 15 seconds: zero core/output shortages, approximately 0.49% mean render budget, 2.46% recent p95 and 99.999% output-clock coverage. Actual playing frames, nonzero DSP samples and drum voices were observed. An earlier intermediate run had one 512-frame output shortage despite a fast core; that failure remains recorded. No buffer expansion or weakened zero-shortage gate was used to obtain the final pass.

The independent heavy fixture uses four filled 64-step tracks, legal 240 BPM/1:32/ratchet x4 settings, shared synth polyphony and drums, inserts and global effects. Three bounded host variants were compared; mixed FM6/PHYS/GRAIN was the heaviest measured, not a proven global worst case. The 120.07-second final simulator run passed with zero missing core/output samples over 5,291,520 output samples, 99.932% output-clock coverage, 5.32% mean render budget and 11.79% recent p95. It observed eight shared synth voices (4/2/2), six drum voices, twelve grains, all four tracks, all instrumented effect configuration flags, 10,586,094 nonzero DSP samples and 121 balanced repeated pad attacks. Configuration flags do not prove each effect is independently audible.

Owner flash SHA-256: `486441dff06e3d0fda51b7fcb4643a2297770bcd9035291734f243b3c98e2e02`; isolated heavy flash: `ff7985162196490ca4d888fc83bc879f075150d7adce5c33684d92cd5650e3b7`. Owner files were copied after the user stopped playback and allowed firmware autosave; stress data never replaces that project.


### Physical native validation and local delivery

The signed device build used frozen core `2a97672aa41b6027a1c21b6476c250770f7ee1fc30b963f529151d498a91a527`. App/test source bytes and all 45 native build-source hashes matched the frozen simulator/device receipts. Tests ran on the paired iPhone 12, with 48 kHz hardware output / 44.1 kHz firmware source, Low Power Mode off and nominal final thermal state. Test-only directories under `Documents/PerformanceFixtures/native-sloop-build5/{owner,heavy}` and isolated preferences kept test writes away from the owner's firmware library.

| Physical scenario | Measured duration | Mean render budget | Recent p95 | Missing core/output samples |
|---|---:|---:|---:|---:|
| Saved owner drum loop plus 8 Hz repeated pad | 30.009 s | 3.114% | 4.339% | 0 / 0 |
| Four-track/effects heavy fixture plus repeated pad | 120.019 s | 18.636% | 19.999% | 0 / 0 |

The heavy case delivered all 5,292,882 requested output samples, with approximately 100% output-clock coverage. It observed eight synth voices (4/2/2), six drums, twelve grains, all four active tracks, configured effect mask 2047 and 10,589,306 nonzero DSP samples. Both warmup periods also had zero missing core/output samples. These are measured workload passes, not a universal worst-patch or all-firmware claim. Listening and long-session thermal acceptance remain separate.

Reports: `Research/Performance/native-physical-build5/{owner,heavy}.json`; result bundles `build-device/NativeSloop5Final/{Owner,Heavy}.xcresult`. Clean Release 0.3.0 (5) passed strict deep signature verification, installed and launched successfully. Device app inventory confirms version/build. No uninstall, store upload or publication occurred. Detailed save-retention verification follows separately; the pre-install owner backup remains preserved.


The post-delivery retention audit compared active firmware autosave generations rather than stale slots. Every complete track block (notes, drum steps and engine/track parameters), user sample slot, stored section, preset, FM6 bank and setting is preserved. The 19 differing raw bytes are confined to an updated autosave A sector; its active project differs only in global Swing (raw 0→81) plus checksums. Its origin is unknown; current phone data was retained without rollback. Both active projects pass CRC/FNV validation. Other firmware packages and Stock/Felucca flash copies are byte-identical. Private detailed receipt: `Research/SequencerDiagnosis/retention-native-build5.json`.


## Touch and native LED regression — 0.3.1 (6)

The bottom-edge miss was reproduced with actual synthesized HID input, not only geometry tests. A 250 ms press at screen-bottom minus 1 pt produced no UIKit events because the root view had 3 pt of bottom padding outside `HardwarePanel`. Removing that gap made the same test deliver began/down/up, before finger release. The view also defers bottom system gestures; simulator HID tests did not independently establish system-gesture arbitration as a cause. Eight taps on each keyboard row, two fingers sharing one key and a slide between keys passed without stuck/released ownership errors. The fixed simulator run measured max began delays of 22 ms on the lower row and 10 ms on the upper row. Test observability is opt-in and transient.

Firmware light and local finger state are now separate: the key body/slit follows the finger immediately and a small independent lamp displays continuous firmware brightness. Pixel checks ensure full firmware activity does not paint the finger slit, while low-brightness guides remain distinguishable. Native LED categories had incorrectly been normalized as 3/2/1; they now use the same physical duty fractions as the interpreter. Native UI/LED timers also moved from 15 Hz host snapshots to the audio-driven 16 ms firmware loop. Snapshots are read-only; tests verify approximately 60 UI frames per audio second and audio-timed hit-light expiration without snapshot polling.

SLOOP's drum behavior intentionally aliases an upper black key to the white drum key on its left; activity LEDs identify that white key. The implementation preserves this source behavior rather than forcing both rows to have identical firmware lights.

A second native input defect was reproduced: key-down and key-up inside a single 512-frame host production batch could collapse to no onset. A bounded per-key transition FIFO now preserves such taps while coalescing chord edges; a 5 ms tap produces audio and a 20 ms control retains the exact old PCM fingerprint. Repeated edges, overload bounds/final release and normal chord behavior are covered. Independent review caught queued notes surviving Pause; explicit release-all now cancels queued note/button presses on Pause while retaining ordinary release-tail semantics and the interpreter's prior releases. All 75 Rust workspace release tests pass; the pause fix was independently reviewed.

The owner confirmed stopping the firmware sequencer and allowing 25 seconds to save. A new read-only backup is in `Research/TouchLedDiagnosis/phone-user-saved-build6`; its SLOOP flash SHA-256 is `96f303d88511f6a5ce43ea9e251f7242561437ea89b8e4a004cf5961572e747a`. No clear/reset feature was added.


### Final build-6 integration

The final reviewed archives are simulator `6d75268fd0b661077e76e0f000dd22ea8030e5db44e9ffe7bba39069dc1a4264` and device `1e3e7ad4fa8c98ce8ccbd25200a330ce8dcbf81351860575b3b6e2a766751789`. All 25 app/test source files and both 45-file native source receipts match the frozen builds. Final simulator owner96/30-second and heavy/120-second cases passed with zero core/output shortages and zero dropped key transitions. Owner mean/recent p95 were 0.506%/0.837%; heavy mean/recent p95 5.247%/12.922%, with all 8 synth/6 drum/12 grain peaks confirmed and queue high-water 2. Seventeen focused Swift tests passed. Fixture state was restored and the simulator shut down.

Physical iPhone 12 HID tests passed both cases: eight taps each on lower F3 and upper F-sharp3, a 250 ms hold at screen-bottom minus 1 pt, two fingers sharing C4, and a C4→D4 slide. All began/down/up counts matched, no cancellations/stuck-held state occurred, and bottom-edge input arrived before release. Measured max began delay was 34 ms on the lower key and 18 ms on the upper key; the edge hold kept the aggregate max at 34 ms. Physical result: `build-device/NativeSloop6Final/PhysicalTouch.xcresult`.

The latest owner96 project also passed its physical 30.020-second loop/repeated-pad test: zero core/output shortages across 1,323,882 requested output samples, 3.436% mean render budget, 5.996% recent p95, zero dropped transitions and queue high-water 2. Backend was native, six drum voices were observed, hardware output 48 kHz/source 44.1 kHz, Low Power Mode off and thermal state fair (1). Report: `Research/Performance/touch-led-physical-build6/owner.json`. Final heavy-device and delivery results follow below.


Final physical heavy stress also passed: 120.018 seconds, zero core/output shortages across 5,293,323 requested output samples, 18.721% mean render budget and 21.481% recent p95. Eight shared synth voices, six drums, twelve grains, all four tracks and configured effects were observed. Dropped key transitions were zero; queue high-water was 2. Thermal state remained fair (1), Low Power Mode off. Reports: `Research/Performance/touch-led-physical-build6/{owner,heavy}.json`; physical bundles under `build-device/NativeSloop6Final/{Owner,Heavy}.xcresult`.

Clean signed Release 0.3.1 (6) installed and launched successfully; installed-app inventory confirms version/build. No uninstall, store publication or reset/clear feature occurred. Owner files were re-copied read-only after delivery for retention verification; all package files and Stock/Felucca flash are byte-identical to the pre-update backup. The active SLOOP autosave comparison is recorded below after checksum-aware analysis. Delivery receipts are in `build-device/NativeSloop6Final`.


Post-delivery checksum-aware audit: current valid SLOOP project advances autosave generation 3→4, changing 61 raw bytes only in autosave B. Tracks 2/3/4 remain byte-identical, including the five recorded drum events; samples, stored sections, settings, presets and FM6 banks are unchanged. Track 1 has six newly filled monophonic steps (0,2,6,9,12,14), preset 0→1 and associated parameter changes; global Swing changes 81→26. Attribution is unknown. The latest valid phone state is retained, with both backup generations preserved; no rollback was performed. Source/path review found no owner-Firmwares write route in the paused HID test or isolated audio tests. Full receipt: `build-device/NativeSloop6Final/retention-detailed.json`. All three package files and Stock/Felucca flash are byte-identical to the pre-update backup.


## Control haptics and fine adjustment — 0.3.2 (7)

Panel/function/piano button presses and the compact toolbar use a soft UIKit impact; encoders and MASTER use selection feedback on real detent changes. Haptics run on the main thread, after dispatching the control action; neither the audio callback nor the native worker invokes feedback generators. A shared 50 ms gate coalesces chords and rapid drag events. Key releases and firmware LED updates do not trigger haptics. MASTER emits no feedback when clamping leaves its quantized ADC value unchanged.

Drag sensitivity changes from 3 to 4 points per detent (25% fewer steps for the same motion). Consumed-anchor remainder and reversal behavior remain intact, MASTER keeps its prior 0.015 volume increment per detent, and accessibility adjustment remains one step. Three focused tests cover threshold/remainder, reversal/large motion and feedback rate coalescing. Nine final simulator checks passed including actual bottom-edge/multitouch HID and existing finger/firmware lamp rendering checks. The final source freeze covers 27 app/test files. Core/audio implementation is unchanged and its 45-file source receipts still match; the generic Rust workspace regression also passed 63 tests. Haptic sensation cannot be accepted in the simulator and requires use on the physical phone.

Signed clean Release and test/UI artifacts are under `build-device/NativeSloop7Final`; their source freeze and strict signatures were verified before delivery. Physical execution/delivery results follow below when complete.


Build 0.3.2 (7) was subsequently installed and launched on the paired iPhone 12. Device inventory confirms the version/build; all three firmware packages and all three flash files remain byte-identical to the fresh pre-install copy. Receipts: `build-device/NativeSloop7Final/{install,launch,apps,retention}.json`; private backup: `Research/HapticsBuild7/before/Firmwares`. Physical haptic feel is left for the owner to assess; no physical sensory acceptance is claimed.


## Automatic startup and lifecycle resume — 0.3.3 (8) implementation stage

Real app appearance/activation now starts the remembered/default installed firmware. Model construction alone remains idle for isolated tests. Inactive/background transitions pause and checkpoint without changing manual intent; active return reconciles the latest intent, including return before stop/save completes. Explicit Pause stays paused across warm Home/return within the same process; a fresh normal process launch starts automatically. OS interruptions, output disconnect and failures retain separate holds; interruption-ended without shouldResume and lost outputs require explicit Play.

Thirteen targeted model/policy/selection tests passed, including suspended-worker pause/load/activation races, interruption cases, retained failure holds and a deterministic stale-failure/explicit-retry regression. Ticketed completions and an explicit retry epoch prevent old worker results from overriding newer user intent. Independent review passed. The real simulator UI case passed cold-launch Running → Home/return Running → manual Pause → Home/return Paused → Resume Running, checking actual runtime status. Existing repeated-row/bottom-edge HID also passed. Test application fixture paths and preferences are isolated; normal/HID/XCTest startup guards avoid accidental owner-project playback during tests. This stage was committed before the requested separate button-haptic repair; physical delivery will use one combined final build. Native core is unchanged.


## Combined lifecycle and button-feedback delivery — 0.3.4 (9)

The already-present button feedback now uses an unattenuated standard light impact, prepared at panel appearance, scene activation and touch beginning. The shared 50 ms cap, knob selection feedback and four-point detents remain unchanged. Five feedback tests cover dispatch, preparation, cap sharing, new press versus held/released keys and read-only redraws. The broader Debug set passed 17 tests; final frozen Release passed 11 focused checks plus all three real simulator UI cases. The unchanged generic Rust workspace passed 63 release tests. Source/signature receipts match the clean device build. Physical sensation is not established by dispatch tests.

On the paired physical iPhone 12, all three UI tests passed with no skips or failures: actual cold-launch Running, Home/return Running, explicit Pause surviving Home/return, and Resume Running; repeated taps on both key rows and screen-bottom minus 1 pt; same-key two-finger input and keyboard slide. Lower/upper maximum began delays were 22/17 ms, with balanced events, no cancellations or stuck keys. Lifecycle testing used a copied SLOOP library and isolated preferences under Documents/PerformanceFixtures/lifecycle-build9. Result: build-device/NativeSloop9Final/PhysicalUI.xcresult.

Clean signed Release 0.3.4 (9) was installed without uninstalling and launched normally. Device app inventory confirms version/build. Fresh read-only copies before tests and after delivery show all three firmware packages and all three saved flash files byte-identical. Backups: Research/Build9Delivery/{before,after}/Firmwares; install, launch, inventory and retention receipts: build-device/NativeSloop9Final. The owner still needs to assess the physical button vibration. No audio performance or new firmware compatibility claim is added.


## Illustrated app icon — 0.3.5 (10)

Added an original generated lavender miniature FM-1 illustration as an opaque 1024×1024 universal AppIcon asset, with AppIcon selected in both generated target configurations and the project generator. Prompt/provenance: docs/app-icon.md. Signed Release compilation and strict deep signature verification passed; compiled Info.plist declares AppIcon for iPhone and iPad. Native audio archive remains the build6-final device archive (1e3e7ad4…). No runtime behavior changes or new audio benchmark claims.

Installed and launched locally on the paired iPhone 12; device inventory confirms 0.3.5 (10). No uninstall/reset. All six firmware/save files are byte-identical between fresh pre-update and post-install copies. Receipts: build-device/Icon10/{install,launch,apps,retention}.json; private backups: Research/Icon10/{before,after}/Firmwares. Asset/build checks replace unrelated behavioral tests for this icon-only update; home-screen appearance remains subject to owner visual acceptance.


## Retail finish correction — 0.3.6 (11)

Rechecked all six names/material combinations against the official product data and full-size front photographs; sources and limitations are recorded in docs/panel-finishes.md. Purple is lilac/periwinkle rather than pink; Orange uses muted burnt orange/terracotta rather than bright orange/charcoal. Black, Black-Green, Cool Gray and White-Blue were also corrected. All knobs now remain black, silicone keyboard surrounds use their matching palette, idle control legends/slits follow the finish and outlines follow the silicone rather than light shell colors. Stored finish names, pressed indicators, firmware LEDs, input and audio behavior are unchanged.

Final Release rendering review exported all six palettes, and both existing geometry/firmware-lamp tests passed (three total cases including a temporary six-finish attachment exporter). Result: build/Palette11Final.xcresult; exported renders and temporary exporter source are retained privately in Research/Palette11Final, not added as a permanent assertion-free test. Final signed device build passed and strict deep signatures verified. No new audio performance claim.

Installed without uninstall/reset on the paired iPhone 12; inventory confirms 0.3.6 (11). All six firmware/save files are byte-identical between fresh pre-update and post-install copies. Receipts: build-device/Palette11/{install,apps,retention}.json; backups: Research/Palette11Delivery/{before,after}/Firmwares. Normal post-install launch was denied because the phone became locked; installation succeeded and owner can open it after unlocking. Simulator visual matching is not calibrated physical color acceptance.

## Experimental SLOOP WebAssembly mode — 0.3.7 (12)

Added a native top-bar SLOOP engine menu: Native remains the default, while
Experimental WASM runs the accepted generic binary translator in WKWebView.
The existing native panel controls both. A dedicated Worker owns emulation and
dynamic WASM compilation; the AudioWorklet only consumes a bounded PCM queue
and converts output sample rate. No PCM passes through Swift. The guest clock
stays at 240 MHz; the source-native SLOOP backend and frozen native archives are
unchanged. No firmware package is bundled. Module SHA is `d4cf83ba…`;
packaging verifies the complete pin before building.

WASM keeps a separate flash branch, initially seeded from the current native
project. Switching checkpoints the outgoing engine and preserves manual pause
intent. Reviewed recovery paths retain the latest durable checkpoint when
startup, restore or pause fails, and permit explicit recovery to Native.
Meaningful Node tests execute the actual package/module, validate flash and
nonzero PCM, generated regions, 44.1-to-48 kHz conversion, queue bounds,
generation rejection and bounded startup failure. Independent source review
passed; iPhone audio, speed and user acceptance are separate gates.

The clean signed Release app was installed without uninstall/reset on the
paired iPhone 12; inventory confirms 0.3.7 (12). Immediately after installation,
all eight existing packages and eight flash files across Documents, including
test fixtures, were byte-identical to the fresh user-confirmed pre-update
backup. The owner library itself contains three packages and three legacy flash
files. One diagnostics JSON changed; it is not a saved project. Receipts and
frozen sources are under `build-device/ModeSwitch12/`; backups and retention
comparisons under `Research/ModeSwitch12/`. Final simulator UI and physical WK
verification results follow below. No new universal
performance or physical audio acceptance follows from installation.

Final simulator checks passed: 23 native/transaction regressions, the actual
WK Worker/AudioWorklet test, and the production top-bar mode/lifecycle UI smoke
(2/2 final integration cases, no skips). The actual WK run reports 329 generated
regions, zero compilation failures and 215,794 nonzero produced samples using
the pinned module at 240 MHz. It delivered 138,111 of 140,160 output frames with
2,049 underflow frames; this short functional smoke is not a real-time or
listening pass. UI coverage includes manual Pause surviving Home/return and
explicit return to Native. Generic Rust workspace: 63 release tests passed.
The owned simulator was shut down before subsequent performance research.
Results: `build-mode12-final/FinalWKMenu.xcresult`,
`Research/ModeSwitch12/simulator-actual-wk.json`; independent review:
`Research/TraceOracle/app-integration-source-review.json`.

The isolated physical WK test subsequently passed on iPhone 12 (iPhone13,2):
320 generated regions, zero compilation failures and 193,400 nonzero channel
samples. Actual C4 input, PCM acknowledgement and separate-save round trip
passed. Audio performance did not pass: 13,825 of 161,408 output frames were
missing (8.57%); mean render budget was 91.1%, p95 147.5%, thermal state fair.
The Web Audio context used 44.1 kHz while hardware output was 48 kHz. This is
a functional smoke, not a sustained real-time or listening acceptance.
Result: `build-device/ModeSwitch12/ActualPhoneWK.xcresult`; metrics:
`Research/ModeSwitch12/physical-actual-wk.json`.

After testing, the clean non-test Release was reinstalled and launched normally;
inventory still confirms 0.3.7 (12). A later read-only retention check found
15 of the original 16 package/save files byte-identical. Native SLOOP advanced
autosave generation 38 to 39 and changed active pattern contents; attribution
is unknown while the owner was also testing. No rollback was performed. The
prior generation remains intact in native autosave copy B, the new separate
WASM flash branch and private backups. Stored sections, samples, settings and
preset banks are unchanged. Source audit found no concrete save-path isolation
defect, but does not establish runtime attribution. Receipts:
`Research/ModeSwitch12/{final-retention,retention-semantic-audit,retention-source-followup}.json`.

### Subsequent local flash-transfer and diagnostic correction (not yet delivered)

WASM flash snapshots now copy into an independent transferable buffer; the page
host performs base64 encoding after receipt, preserving Swift's existing wire
format. The emulation Worker's linear memory is never transferred. Diagnostics
separate input, context and hardware sample rates, cumulative output-counter
duration and current playback-session duration, and report the actual maximum
render ratio. The generic module and 240 MHz clock remain unchanged.

Three Node tests passed, including actual transfer/detachment, byte-exact snapshot
independence and existing PCM/command sequencing. Independent source review
passed. The focused Release simulator suite passed 4/4 cases: actual WK
1 MiB saved-flash equality plus three transaction/recovery cases. Swift compiled
successfully and built resource pins match the frozen source. Result:
`build/FlashTransfer/Focused-testable.xcresult`; receipt:
`Research/ModeSwitch12/FlashTransfer/receipt.json`.

An exploratory old/new audio-paced pair observed flash work moving off the
producer, but focus/occlusion changes and concurrent browser activity confound
its performance comparison. It establishes no causal dropout or throughput gain.
The earlier timer microprobe's nesting delay also did not recur in the actual
audio pipeline, including synthetic starvation; no timer fix was applied.
The observed iPhone render-budget deficit remains unresolved. Details:
`Research/ModeSwitch12/{PipelineAudit/REPORT,FlashTransfer/RESULTS}.md`.

### 0.4.0 (13): five source-native engines and menu profiling

The combined release core passed 79 tests and both arm64 Apple archives were
frozen with exact source/resource receipts. Native releases are SLOOP 2.7.1,
Felucca 1.6.1, X0X 1.1.0, Melodee 1.4.3 and FM1 Open V13 Official Preview.
The last uses M-VAVE's public browser-instrument C engine, not the proprietary
hardware SDK. See [native engines](native-firmware-engines.md) and
[official preview](native-official-preview.md) for compatibility boundaries.

The current Release simulator suite completed 51 cases: 44 passed and seven
explicitly opt-in performance cases skipped, with zero failures. It includes
actual App routing/save/reopen for all five, byte-exact preservation of raw
hardware-emulator flash alongside the preview's smaller logical store, actual
WK audio and flash transport, mode/clock rollback, exact native catalogue
classification, resource notices and display-state isolation. The old import
test was changed to use a temporary library and a real attached InstrumentView:
unmatched Stock now starts through WebKit, so an unhosted model is not a valid
playback test. The new test checks a successful running Stock import, filename
deduplication and preservation of the raw flash. Result:
`build/MenuProfileNative13/FullModels-r2.xcresult`.

Actual generic-module Node tests passed at 120, 180, 240, 320 and 360 MHz,
including verification of the real CPU boot argument, complete initial flash,
nonzero PCM, bounded buffering and command/pause sequencing. The default remains
240 MHz. Native source timing is unchanged. The packaged universal engine is
the previously independently checked normal-forward/reuse candidate, SHA-256
`d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87`.
These checks do not establish sustained phone throughput for every FWSC.

Matched native menu runs used the same final core, local SLOOP package, fresh
isolated projects and interaction sequence on the owned iPhone 12 simulator.
Catalogue decode/sort operations fell from 299 to one, library descriptions from
577 to 11, and root descriptions from 728 to 39. The catalogue is cached;
display/LED publication no longer invalidates the menu model; validation/staging
and directory refresh run outside main-thread view construction. Instrumented
panel drawing remains about 4.5–4.7 ms per draw in these runs. Display-link
delivery mean changed from 73.96 to 48.91 ms and p95 from 147.55 to 98.97 ms.
Those intervals include headless-simulator/XCTest scheduling and normal sheet
animations: they are neither calibrated touch latency nor a 60-fps/phone pass.
Reports: `Research/MenuProfile/{baseline-native13-r2,final-native13}.json`.
Earlier traces with an invalid fixture/startup alert were excluded.

The clean signed Release passed code-signature/resource verification and was
installed without uninstalling on the owner's iPhone 12. Inventory confirms
0.4.0 (13). Fresh Documents and preferences were copied before replacement;
all seven pre-existing firmware/save files remained byte-identical immediately
after installation. Three missing package files were added; existing exact
SLOOP/Felucca packages and their identities were reused. All five full package
hashes matched the linked registry. These are installation/initial-retention
receipts, not final physical audio or UI acceptance. Isolated physical QA and
profiling are recorded separately after completion. Local receipts:
`Research/Native13/{device-clean-receipt,installed-app,post-install-retention,web-clock-matrix}.json`.

Isolated physical iPhone 12 functional QA subsequently passed seven tests with
zero skips or failures in 56.72 seconds: all five native routes/save/reopen,
actual WK signal/flash, and five transaction/recovery checks. The tests used
temporary projects and a separate empty app-host library. Result:
`build-device/Native13Tests/PhysicalModels.xcresult`.

The short actual WK smoke compiled 325 regions without failures and produced
audio, but missed 5,761 of 161,408 output frames (3.57%). Mean render budget was
82.48%, recent p95 135.40%, with a startup maximum of 1,521%; thermal state fair.
Context/input ran at 44.1 kHz and hardware at 48 kHz. Universal-WASM sustained
real-time acceptance remains failed. These conditions differ from the earlier
phone run, so the lower shortage percentage alone does not establish a causal
speedup. Report: `Research/MenuProfile/physical13-actualWK.json`.

The real nested clock-menu UI path passed on the simulator: Native to WASM,
manual pause across Home/return, 240 to 180 MHz while retaining pause, then
return to Native (`build/MenuProfileNative13/ClockUI-r2.xcresult`). The physical
menu/search/scroll/settings sequence also passed while native playback was
running (`build-device/Native13Tests/PhysicalMenus.xcresult`). Its asynchronous
frame report did not flush before test teardown, so no physical UI frame timing
is claimed. A separate fresh native SLOOP fixture ran for 48.445 seconds with
2,134,440 delivered frames and zero output/core shortages; mean render budget
was 0.3372%, p95 0.7206%. This was an idle/light project, not maximum polyphony.
Use `physical13-native-fixture-audio.json`; the earlier similarly named menu
audio file was stale owner diagnostics and is excluded.

A final eight-second simulator Time Profiler recording succeeded with named
stacks. Of 4,845 one-millisecond app CPU samples, 4,673 were on the main thread
(96.45% of app samples, approximately 56.36% of one core over 8.292 seconds).
Main-thread leaf samples were dominated by CoreGraphics axial-gradient shading
(1,895), image marking (1,052) and antialias rasterization (452). Named
`HardwarePanel.draw` accounted for 586 inclusive samples; much drawing work is
deferred into Core Animation display/rasterization, so that method's own timing
does not capture the complete cost. The two audio I/O threads totalled 102
samples. This identifies **idle simulator panel rasterization**, not physical
phone CPU or heavy DSP, as the next UI rendering target. Cache static artwork
and avoid repainting the complete panel for every LCD/LED update before drawing
conclusions about another firmware engine. Trace and extracted statistics:
`Research/MenuProfile/final13-sim-cpu.trace` and
`Research/MenuProfile/final13-sim-cpu-summary.json`. The physical trace attempt failed:
Instruments reported the device offline while CoreDevice installs/tests worked.
No physical CPU sample attribution is claimed.

After testing, the original clean signed Release was reinstalled and launched
normally. Fresh diagnostics confirm the owner's remembered SLOOP identity,
native backend, automatic audio start and output consumption. All three original
preferences are unchanged; all five exact package hashes remain present.
Six of seven original firmware/save files remained byte-identical at final
retention. The SLOOP working autosave advanced, with unchanged working
notes/steps/microtiming/locks, a track-selection/chord-setting change, and edits
to stored section A; other stored sections remained unchanged. The former
working generation remains intact in its alternate live copy and the complete
pre-install backup preserves the earlier stored section. Attribution is unknown
while the owner also tests the app; no rollback or overwrite was performed.
Receipts: `Research/Native13/{final-retention,retention-semantic-audit-summary,final-owner-launch,final-owner-audio}.json`.


## UI rendering, collapsible controls and finish palettes — 0.4.1 (14)

The panel now composites cached static artwork, key-face sprites, LCD pixels,
LED opacities and knob-marker rotations in Core Animation layers. Snapshot
updates no longer repaint the full gradient panel. Only the active bounds,
scale and finish artwork is retained; same-finish refreshes reuse it. Layout
invalidation covers refresh-before-layout ordering and transient tiny bounds.
Resizing during a held knob drag reanchors the gesture without adding a detent;
held notes remain held. The chevron has a 44-point target in the trailing gutter,
persists its collapsed state and keeps the same instrument instance. On iPhone
12, hiding the header increases both the panel and LCD size. It does not change
firmware, audio or the explicit Play/Pause choice.

All six finishes have separate LED/pressed palettes and adjusted legend ink;
normal and pressed legend contrast against both gradient endpoints is at least
4.5:1 in the palette tests. Firmware LCD pixels are unchanged. Palette values
are a UI rendering choice; this is not a new colorimetric hardware-match claim.

A controlled eight-second Time Profiler comparison used the same simulator
(iPhone 12), pinned native SLOOP, Black finish and expanded header, without
concurrent builds or UI automation. Baseline main-thread sample weight was
4,604 ms over 8.23844 seconds (55.88% of one core); final was 302 ms over
8.26359 seconds (3.65%), a 93.46% reduction. The previous dominant axial-gradient
and image rasterization leaves are gone from the leading stacks. This measures
idle simulator UI CPU, not phone CPU, DSP throughput, maximum project load or
end-to-end latency. Reports: `Research/UI14/{baseline-summary,final-summary,cpu-comparison}.json`.

The broad Swift regression run completed 58 cases with seven expected opt-in skips
and no failures
before the final layout guards. The final focused panel, geometry, palette and
feedback run passed all 16 cases. Seven final simulator UI cases passed,
covering header geometry/persistence/both landscape orientations, running and
paused intent, menus/search, bottom-edge multitouch/sliding, and Native/WASM
clock selection. The first focused run's exact CGRect equality differed only
by floating-point rounding; a 0.001 tolerance assertion passed on rerun without
changing app source. Functional UI runs overlapped a device build, so their
frame metrics are not presented as a controlled performance comparison.

The clean signed Release 0.4.1 (14) was installed over build 13 on the owner's
iPhone 12 after explicit save confirmation and a fresh Documents/preferences
backup. All 13 existing firmware/save files were byte-identical immediately
after installation, and all seven original application preference values were
retained. Normal owner launch restored native SLOOP automatically. Fresh phone
audio diagnostics delivered 1,065,897 of 1,065,897 requested frames with zero
output shortages and zero missing core frames; this short owner-start check is
not a maximum-load or listening test. No firmware/core rebuild or owner-file
restoration was performed for this UI update. Installation, signature/source,
retention and audio receipts are retained privately in `Research/UI14/`.

A final compact-screen simulator check on iPhone SE (3rd generation) passed
header growth/persistence/menu access and both landscape orientations. Twelve
full-screen finish captures (six expanded/collapsed pairs) were exported and
visually checked. The initial app-only XCTest captures carried incompatible
orientation metadata; the evidence was recaptured using XCUIScreen without
changing app source. Final captures: `Research/UI14/FullscreenFinishCaptures/`;
compact result: `build/UI14/SE3Header.xcresult`.


## Panel spacing and key definition — 0.4.2 (15)

Centered MASTER/PRESETS and SELECT/ALGORITHM above the OCT−/OCT+ column centers,
bringing each left pair inward. All eight knobs share the same layout-constrained
diameter; the four right knobs were reduced to match the left group. Keyboard
keys have an inset 1.3-point contour tinted from the finish's key face and legend
colors. Pressed contours retain the finish accent. These remain cached artwork;
no audio, firmware, haptic timing or snapshot scheduling changed.

Release simulator build passed 16 affected unit tests (geometry, palettes,
render cache and feedback) plus four real UI cases: six-finish captures,
header growth/persistence/both landscape orientations, bottom-edge repeated taps,
and multitouch/sliding. All six finishes were visually inspected in full-screen
captures. Signed device Release 0.4.2 (15) and strict signature validation passed.
Reports and twelve expanded/collapsed views: `Research/UI15/`; XCTest result:
`build/UI14/Visual15.xcresult`. No new CPU/DSP benchmark is claimed for this
cosmetic revision.

After a new explicit save confirmation, fresh Documents/preferences were backed
up and clean Release 0.4.2 (15) installed on the owner's iPhone 12. CoreDevice
inventory confirms this version. All 13 original firmware/save files remain
byte-identical and all eight original preference values are retained. The app
was launched normally, with no fixture environment or owner-file restoration.
Receipts: `Research/UI15/{backup-manifest,install-clean,installed-app,post-install-retention,final-owner-launch}.json`.


## Native-only consumer preparation — 0.5.0 (16), 2026-10-19

The upper piano keys now use a half-pitch offset instead of 0.64 pitch, centering
each between its lower neighbours without changing note IDs. A geometry test
checks three adjacent pairs at expanded/collapsed iPhone and compact widths.
The transport has 44-point targets and plain Playing/Paused/Loading status;
Native/WASM, CPU controls and audio counters are removed from the consumer UI.
The library offers only eight exact releases with linked source-native engines,
shows download size before activation, and no longer offers arbitrary Files
import. About retains sound-preview disclosure, privacy information and license
attribution. A published privacy/support policy URL remains a release gate.

Both real app initializers pass nativeOnly:true. Exact-byte package probing and
initial library discovery run on storage/worker queues. Unknown packages cannot
be selected or imported through that instance, even under a convincing filename;
old experimental preferences do not construct a WASM engine. Existing unsupported
packages and separate saves are preserved. Research/test Instrument instances
retain the old experimental APIs; no claim of a stripped store archive is made.

The catalogue is physically reduced to SLOOP2.7.1/Felucca1.6.1/X0X1.1.0/
Melodee1.4.3/FM1OpenV13/Skiff1.3.2/FoMni0.4/Jangada1.0.1. New Skiff/FoMni/Jangada
ports compile actual source application, DSP, display/input and storage code;
all retain physical 1MiB NOR. The official portable preview retains its separate
logical store and hardware-sound caveat. This selection uses source-port
feasibility and dated public interest signals, not a claimed top-eight install
ranking. See native-skiff.md and native-expansion.md for exact pins and scope.

The corrected all-eight Rust release workspace passed 81 tests with zero
failures, including non-silent public-ABI audio, full-store reopen and independent
instances. Source review found and corrected a FoMni encoder-role permutation;
the final public-ABI regression covers all seven physical encoder IDs, the full
source parameter vector, both storage CRCs and reopened logical project checksum.
Its PRESETS test uses physical ID6. The earlier archives were explicitly rejected
and retained under Research/NativeExpansion/superseded, never used for delivery.
The final corrected simulator archive SHA is
3c2f1c2eab3c82f7dc540479aa5f043b937e1918aa17b0e8b800e995180182bb;
device SHA fbc2482773f777e87c7c277870e8d1cbd6a1e56b6aaa3632ea3813a495ac38fd.
Both receipts verify 69 implementation and 56 notice files without drift.
Evidence: Research/NativeExpansion/validation.json and the final archive receipts.

The full Release simulator Swift suite completed 64 cases with seven explicit
opt-in stress/performance skips and zero failures. It includes actual eight-route
native save/reopen, old-WASM-preference migration without touching its save,
unsupported-package rejection/retention, exact catalogue classification, bundled
credits, native lifecycle, real hosted WK research regression and unique friendly
staging filenames. New downloads now use a unique parent directory with a normal
release basename so temporary UUIDs do not leak into the selected instrument name.
Result: build/StorePrep16, Research/StorePrep/swift-validation.log.

The clean signed device build 0.5.0(16), strict signature verification, packaged
8-entry catalogue and PrivacyInfo.xcprivacy were verified. The privacy manifest
declares private UserDefaults(CA92.1) and elapsed in-app timing(35F9.1), no tracking
and no collected-data types; a final archive/dependency privacy audit is still
required. Research WASM resources remain in this development bundle. App Store
submission, distribution rights for GPL/sample banks, final branding, policy/
support URLs, oldest-device acceptance and a separate native-only store artifact
remain explicit gates in app-store-preparation.md. No upload or publication was
performed. Device build/receipt: Research/StorePrep/device-clean-receipt.json.


Final consumer UI coverage is green: the requested functional cases on
iPhone12 are satisfied across the main run and the targeted About retest; the
original failure was an overlong XCTest scroll gesture, repaired in test code.
Both SE3 compact Header/Menu cases and both iPad-mini Header/Menu cases passed.
Twelve unsupported-package/save sentinel files remain byte-identical. Live native
SLOOP screenshots were visually checked in expanded/collapsed phone layouts and
on iPad; no transport overlap or LCD clipping was observed. The iPad's broad
vertical spacing still warrants a dedicated visual polish pass before release;
geometry/menu success is not a complete tablet design acceptance.

A final small product change exposes Skiff's complete bundled third-party
attribution text directly in About. The affected bundled-notice unit test and
About navigation/readback case both passed after that change. No native engine
or loader source changed. Both final signed device artifacts were rebuilt; the
clean app's source hashes/signature were rechecked. All owned test simulators
were shut down. Detailed case results/initial failure/targeted reruns are in
Research/StorePrep/qa-summary.json; screenshots in ConsumerCaptures/.

This task has not installed16 on the physical phone: fresh owner save confirmation
is pending. The last delivered phone build remains0.4.2(15). No phone files were
changed or new physical-device performance claims made during this preparation.

## Native glass and SLOOP file workflows — 0.6.0 (17), 2026-10-19

Projects and files is now an actual SwiftUI sheet, reachable from a 44-point
folder in the reserved side gutter with the header expanded or collapsed.
Navigation/actions use iOS 26+ Liquid Glass, finish-specific tint and a material
fallback on older supported systems. Reduce Transparency has an opaque fallback.
The firmware library, color picker, About and enlarged display also follow the
selected finish. The progress group keeps Cancel accessible as a separate control.

SLOOP 2.7.1 supports named project copies, typed checked import/open, complete
workspace backup, WAV preview/trim/normalization-off import into USR1–USR4, and
stereo PCM16/44.1 kHz WAV rendering from a separate captured native instance.
MIDI files, live recording, stems and other engines' typed interchange are not
implemented or advertised as available. See project-files.md for exact scope,
shared-bank effects, schema, limits and recovery behavior.

Projects preserve the current global settings/MIDI map/theme/MASTER when opened;
full backups restore all workspace components. Shared project payloads scrub
unused raw storage and unrelated preferences. Sample application rebases on the
latest worker-boundary capture. Every replacement persists and verifies a full
recovery first; failed candidate, storage or audio start retains/restores the old
instance and automatic save. A parked loop during SONG playback and a SONG REC
pass must be stopped before capture. Explicit default MIDI restoration prevents
an older map in flash from resurfacing. Private project libraries now belong to
their exact instrument directory, including isolated UI fixtures.

All-eight Core release workspace: **86 passed**, zero failed, including five new
public typed-bridge regressions. Final simulator archive SHA256:
7da669e7a2db0b40b4ea9d35cecb7c71e2df0ca969a7f5d8ed641365822a0a29;
device: 1b57d426721f91974eaf33883938b1995b5944ab663892ba571b921822b9e979.
Both receipts verify 70 implementation files and notices without drift.
Evidence: Research/StorePrep/project-core-validation.json and
Research/Generated/fm1-project-files-*.receipt.json. Independent source review
found and verified the MIDI-default and parked-SONG fixes before final execution.

The initial complete simulator Swift suite passed **77 cases, seven explicit
opt-in skips, zero failures**. After the final small file/accessibility changes,
all **17 affected tests passed**: six format/scope/privacy/isolation cases, three
actual Instrument/Store transaction cases, six sample cases and two real WAV/
cancellation cases. These include recovery-write failure with playback retained,
bad-checksum nonmutation, sample replacement/project restore/global-settings
preservation and durable reopen. A recorded unsaved musical loop rendered into a
non-silent, decodable WAV of exactly 55,125 frames (1.25 seconds including tail).
Cancellation was requested after real rendered progress. The FSMP slot matches
an independent pinned-upstream Python codec vector byte-for-byte; actual stereo
conversion passes both anti-phase cancellation and same-phase level tests.

The three new transaction tests originally blocked MainActor callbacks with a
synchronous test waiter. The interrupted failed run is retained; their async
wait/teardown correction passes in ProjectIntegrationFinal.xcresult. No product
behavior was relaxed to make those tests pass.

All four requested iPhone 12 simulator UI cases are satisfied across the main
run and final targeted flow retest: collapsed folder reachability/key separation,
section navigation, six finishes x three sections (18 inspected captures), and
real named-copy export followed by five-second WAV preparation and return to
Playing. Initial UI harness failures used a disallowed fixture path, then assumed
a caret position/Select All menu for the suggested name; all original receipts
are retained. The final flow verifies the actual entered name through the saved
copy and friendly exported filename. It verifies prepared Files/Share actions,
not a completed external document-provider delivery or a sent share activity.
Reports/captures: Research/Projects17/, build/Glass17/{UnitValidation,
ProjectIntegrationFinal,FilesUIValidated,FilesFlowFinal}.xcresult.

The clean Release **0.6.0 (17)** iPhone archive and dSYM were built and strict
signature verification passed. This is **Apple Development** signing with
get-task-allow=true, not a TestFlight distribution artifact. Eight catalogue
entries and the privacy manifest are present; firmware packages/test bundles are
absent. The research engine.wasm remains packaged, so the native-only store
artifact audit is still open. Archive: build-device/Glass17/FM1.xcarchive;
receipt: Research/Projects17/device-archive-receipt.json records binary, privacy,
complete App source/resource hashes and intentional final source changes.

No phone installation, App Store Connect mutation, distribution export, upload,
tester invitation, agreement acceptance or author contact occurred. The phone's
last delivered version remains 0.4.2 (15). Current tests use fresh simulator
fixtures, not owner saves. Physical listening/haptics, Files/iCloud destinations,
VoiceOver/Dynamic Type/increased contrast, iPad polish and Apple acceptance remain
separate checks. TestFlight account/signing/rights gates and prepared local-only
internal export options are documented in testflight-preparation.md.

## Internal TestFlight delivery — 0.6.0(17), 2026-10-19

After the owner explicitly authorized TestFlight upload and completed both
Apple sign-ins, the unchanged Glass17 archive exported with valid distribution
entitlements (get-task-allow=false, beta-reports-active=true, exact team/bundle;
strict signature verification passed). App Store Connect record6824659753 was
created, and the real internal-only upload exited0. Apple processing completed
with Ready to Test. The exact build is assigned to Owner Beta, an internal group
with automatic distribution off and exactly one existing Account Holder tester.
Group UI confirms1tester/1build; owner statusInvited. What to Test and beta
description are saved. Evidence: Research/TestFlight/distribution-17.json,
upload-17.log and native App Store Connect screenshots.

The source candidate and prior core/simulator evidence remain unchanged; no new
runtime tests or phone actions were performed for this signing/upload step.
Actual invitation acceptance, remote phone install, save retention and listening
acceptance are pending the owner. No external test group, public link, public
review or App Store release was submitted. Existing source/bank rights and final
public packaging/metadata gates remain open; successful private beta delivery is
not a clearance claim. No legal agreement was accepted by the agent.

## Soft-halo key illumination — 0.6.1 (18), 2026-10-19

User approved the halo option and requested readable dim indication on Purple.
Only App/PanelView.swift and version metadata differ from build17; core archives,
Instrument, display publication, audio and control feedback sources match17.
The central insert carries the keyboard lamp, with a cached local halo, near-white
core and dark recess. No separate keyboard bottom dash or full-face touch hue
change. Firmware duty input, exact zero, brightness ordering, event timing,
geometry and hit regions are retained. A monotonic display response intentionally
lifts dim brightness. See panel-finishes.md.

Independent Sol source review found no blocker. Native initial rendering exposed
insufficient Purple dim contrast; the display response/recess was improved from
actual pixel evidence. A test's lip sample landed outside the thin recess and
was corrected; native contrast checks were retained and expanded to separation
from the key face. Floating-point frame/opacity assertions were corrected rather
than changing product geometry. A first Release test build omitted ENABLE_TESTABILITY;
its build-only failure is retained separately.

Final simulator checks:18tests passed,0failed in FinalValidation.xcresult. They
cover six finishes' actual off/dim/active pixels, lamp/body/sprite caching, held
feedback independence, invalid duty, geometry and haptics. The2actual HID touch
UI tests also passed in LightingValidated.xcresult before the brightness/recess-only
adjustment; geometry/input source is identical. Repeated taps, bottom-edge touch,
two fingers and keyboard slide retain balanced press/release.18nativecaptures
are under Research/Keylight18/NativeCaptures; root inspected Purple dim/active
and Black active. Exact receipts/logs and initial failures are retained locally.

Archive/distribution progress is tracked in Research/Keylight18/verification.json.
No physical phone install, retention, listening or haptic acceptance is claimed
by simulator tests. Public App Store release remains deferred.

The clean18archive/dSYM and strict signature passed; a separate distribution
export verifies get-task-allow=false, beta-reports-active=true and unchanged
team/app identifier. Internal-only upload exited0 and Apple processing reached
Ready to Test. Saved beta notes, then assigned the build to Owner Beta only;
build details verify Internal/1tester. No other group was modified by this update.
Final Testing availability is recorded with screenshot in the local receipt.
Phone installation, save retention and physical visual acceptance remain unverified.

## Compact chrome and finish optics — 0.6.2 (19), 2026-10-20

Only FM1App.swift, PanelView.swift and Info.plist differ from18 among app
sources. External transport/side backplates are gone, the canvas is black and
the header has no extra gap. Both side controls retain44pt targets, move16pt
lower and reuse the landscape gutter with at least12pt physical edge clearance.
Sheets retain their themed glass. Colored finishes receive individual lamp core,
recess and cached-halo styles; Black is unchanged. Firmware/audio/input geometry
and native core archives match18 exactly.

Simulator: iPhone12/iOS27.0, Release test host.20 unit cases passed in
build/Chrome19/Validation.xcresult, including actual six-finish off/dim/active
pixel separation, invalid duty, cached artwork, held feedback independence,
geometry and feedback. All3 Black off/dim/active exported PNGs are byte-identical
to18. A legacy drawing oracle also checks both Black lamp orientations.

The first UI run passed actual SLOOP six-finish captures, playback-intent
persistence and collapsed Projects access in both landscape orientations. It
exposed undersized accessibility/touch bounds on plain top labels:7 size
measurements failed. Explicit contentShape was added after44pt label frames;
no assertions were weakened. The previously failing header case then passed in
build/Chrome19/FinalChrome.xcresult, including both rotations, safe edges, menu
access and persistence.20 unit +4 distinct UI cases have passing results; the
initial failure and captures remain retained. Verbose simulator diagnostics
collection was stopped after the failing run's tests had finished; test output
and attachments were preserved.

Independent Sol reviews found no source blocker in chrome or lamp/cache/duty
changes. Native screenshots and all receipts are under Research/Chrome19/.
Archive/upload/Apple availability are tracked separately in verification.json.
No physical phone acceptance, listening/performance benchmark or public release
is implied by these UI checks.

19 upload exited0 (Upload succeeded/EXPORT SUCCEEDED). A separate distribution
export of the same archive passed strict signature, release entitlements and
team/application identity checks. After upload the browser session expired;
owner re-login was requested. Server Ready to Test, beta notes and Owner Beta
assignment remain unverified/pending; no Testing/phone availability claim.

After owner re-login, build19 (4e9c2a2a-bd92-4b38-b310-6e8311bcd3f4)
was verified Ready to Test. Beta notes were saved and only Owner Beta was added
(Internal,1 tester). Final iOS Builds readback shows0.6.2/19 Testing, Owner Beta,
1 invitation. Screenshot/receipt: Research/Chrome19/testflight-testing.png and
verification.json. No other group modified; physical install/acceptance unverified.

## Compact spacing — 0.6.3 (20), 2026-10-20

Only chrome/version app sources change from19. The transport reserves36pt
instead of44pt, horizontal inset9→4pt and item gaps10→4pt. Its44pt targets
extend8pt into the panel's static top rim; header stacking prioritizes those
touches, with actual LCD/knob targets below. Outside panel inset3→1pt and
side-icon gap8→2pt recover space. Side hit targets44pt, physical clearance12pt
and top offset16pt are retained for the rounded upper corner.

First iPhone12 Release simulator run passed panel geometry and2 UIcases. Final
corner matrix adds real outer-quarter arrow taps and lower-edge header taps,
with both landscape orientations on12,12mini and18ProMax. Results, native
attachments, source/core hashes and distribution state are recorded separately
in Research/Compact20/verification.json. No firmware, lamp or audio sources
changed; no new audio performance/physical phone acceptance is implied.

Final20 checks:3 geometry cases passed. Both UIcases have passing results on
iPhone12,12mini and18ProMax (both landscapes, including physical coordinate taps
near the arrow's outer corner and the header targets' lower edge). Matrix pass
for12/ProMax and miniheader is in CornerMatrix.xcresult; miniFilesRetest passed
in MiniRetest.xcresult. Initial miniFiles case failed only because AX reported
43.999999999999986 for a44pt target; assertions now allow0.001pt numerical error.
The product target remains44pt. Initial result is retained; no functional failure
was hidden or product geometry changed to satisfy the assertion.

Root inspected native12expanded/ProMaxexpanded/minicollapsed screenshots. Signed
archive/dSYM/source freeze and separate distribution export passed checks.
Distribution export confirms get-task-allow=false, beta-reports-active=true and
unchanged team/application identity; its hash identifies a separate export, not
exact uploaded bytes. Upload and Apple status are in the20 receipt.

20 upload exited0 and Apple processing reached Ready to Test. Beta notes saved,
assigned only Owner Beta (Internal,1tester). Final0.6.3/20 readback shows Testing,
Owner Beta and1invitation. Evidence: Research/Compact20/testflight-testing.png
and verification.json. No physical phone install/acceptance or public release.

## Fixed knobs and taller LCD — 0.6.4 (21), 2026-10-20

Firmware selector dot removed. Top label/glyph artwork moves4pt upward inside
unchanged44pt touch targets; the row reserves32pt, recovering another4pt for the
instrument. Its last12pt of hit area sit over the static panel rim. Actual LCD
and knob controls do not overlap those targets. Side safe geometry is unchanged.

PanelView now supplies a compact-height knob reference from the current window,
including when launching with the header already hidden. All eight diameters
are computed from that reference before LCD layout, avoiding feedback from the
expanded display into knob size. Orientation/window resizing still adapts the
reference. LCD uses balanced4pt horizontal insets and can use available width
beyond the former29% cap, while reserving six44pt function keys and four fixed
knobs. The existing square display and keyboard behavior are retained.

NativeValidation.xcresult:13 unit cases and iPhone12 UIcase passed. New geometry
checks cover three phone panel sizes: every knob diameter is stable, LCD grows,
function keys keep their width, and no LCD/control overlap. Existing native
render, cache, duty, held feedback and relayout checks pass. Actual UItest uses
outer-quarter arrow taps, lower-edge transport taps, rotation, persistence and
checks all8 knob sizes across collapse. Root inspected expanded/full captures.
Further corner runs, signed archive and TestFlight readback are recorded under
Research/Controls21/. Native core archives, firmware/audio/input and lamp styling
sources are unchanged; no new physical phone or audio performance claim.

21 final: all3 UIdevice runs passed (12/12mini/18ProMax, both landscape
orientations). A final guard handles nonfinite/tiny reference heights that can
arrive before UIKit bounds during a layout transition; it falls back to valid
current geometry without changing the normal reference path. FinalNative.xcresult
passes14 cases including valid three-size layout invariants and invalid-reference
recovery. UIcaptures/cases precede that defensive fallback; their valid geometry
path is unchanged. Final signed archive is Controls21/Validated.xcarchive, with
strict signature/dSYM/identity/source freeze verified. Initial archive retained
locally but not uploaded. Native core hashes match20.

21 upload succeeded, Apple processing reached Ready to Test, notes saved and
only Owner Beta assigned (Internal,1tester). Final0.6.4/21 readback: Testing,
Owner Beta,1invitation. Evidence: Research/Controls21/testflight-testing.png and
verification.json. No physical phone acceptance or public release implied.

## Anchored knob groups — 0.6.5 (22), 2026-10-20

Only PanelView.swift and version metadata app sources differ from21. The left
knobs form a rigid2×2 square with one shared horizontal/vertical gap chosen
from compact geometry. The entire block is centered above the octave keys;
its upper and lower rows translate together when the transport is hidden.

The right knobs and function grid retain compact vertical geometry. Their
common translation follows the bottom of the upper panel above the keyboard,
so knob-to-function gaps and lower-anchor distance remain constant. Function
button heights do not stretch in full view. Existing fixed knob diameters,
expanded LCD, keyboard geometry and44pt external targets remain unchanged.

Native assertions now cover square cluster spacing, rigid relative positions,
centering, lower anchoring and unchanged right-row/function separation, alongside
size/LCD/non-overlap checks. Final platform matrix, actual captures, source/core
hashes and owner-only TestFlight receipt: Research/Anchors22/. Initial exploratory
validation is kept separately; only final-source evidence is used for release.
No audio, firmware, lamp/input logic or native core archive changed.

Final22 matrix passed on iPhone12,12mini and18ProMax:14 native unit/render
cases +1 UIcase on each (45 device/case runs,0failures). UIcase exercises
both landscapes, collapse/persistence/menu access, outer-quarter arrow/lower-edge
transport taps and the new anchor relationships. Final-source screenshots were
exported; root inspected iPhone12 expanded/full. Source and test hashes match
the signed archive. No further source edits after final validation.

22 upload exited0; Apple processing reached Ready to Test. Notes saved and
only Owner Beta assigned (Internal,1tester). Final reload confirms0.6.5/22
Testing, Owner Beta and1invitation after a temporary empty status field.
Evidence: Research/Anchors22/testflight-testing.png and verification.json.
Physical phone install/acceptance and public release remain unclaimed.

## Compact right-row centering — 0.6.6 (23), 2026-10-20

Right knob placement now centers the visible15pt label + knob face above the
compact function grid. That reference position receives the same lower-anchor
translation as22, so fixed size and right-group attachment persist in full view.
Only PanelView/version app sources change; left cluster/LCD/buttons/keyboard,
audio/firmware/lighting remain unchanged. Native geometry asserts equal compact
visible margins and unchanged lower-anchor/size/LCD invariants at3phone sizes.
14unit/render cases +1real UIcase passed on iPhone12/iOS27.0 (both landscapes,
external corner/lower-edge taps, persistence and menus). Other physical model UI
runs were not repeated for this one-expression placement adjustment. Root inspected
the final compact capture. Signed archive/source freeze/dSYM/identity verified.
Upload/Apple availability receipts: Research/Center23/. No phone acceptance claim.

Apple distribution readback for 0.6.6 (23): upload succeeded, processing completed, What to Test saved, and only the existing Owner Beta internal group (1 tester) assigned. App Store Connect shows Testing with 1 invitation. Proof: `Research/Center23/testflight-testing.png`; receipt: `Research/Center23/verification.json`. Physical iPhone acceptance remains pending; no public App Store release submitted.

### SLOOP file UX and complete-song export — 0.6.7 (24)

The updated file workflow separates named copies, recovery backups, samples and
WAV audio. An explicit Loop/Whole song choice renders on a disposable native
instance. Whole song follows the arrangement to its end once, ignoring repeat,
then adds the chosen tail; missing sections fail before output. The folder is
visible only for the pinned native SLOOP capability.

All-eight native host workspace: 86 passed. Targeted simulator suite: 12 file,
transaction and real-audio tests plus 2 UI cases passed with zero failures.
The song test renders A1+B2 and A1+B1, checks the 3:2 duration relationship,
audible output, unchanged source settings/repeat, exact fixed-duration loop
output and rejection of a missing section. UI verifies SLOOP → Felucca → SLOOP
folder visibility and save/cancel/open/export plus Whole song controls.
Evidence: `Research/Song24/verification.json`, `build/Song24/Validation.xcresult`.
Both native platform libraries retain build23 hashes; the signed 0.6.7 (24)
archive verifies strictly. No new physical-phone or external Files-provider
acceptance is claimed. TestFlight distribution is recorded separately below.

0.6.7 (24) distribution completed: Apple upload succeeded, What to Test saved, existing Owner Beta internal group (1 tester) assigned, and App Store Connect verified Testing with 1 invitation. Receipt and screenshot: `Research/Song24/verification.json`, `Research/Song24/testflight-testing.png`. No public release or physical-phone acceptance claimed.

## SLOOP 2.8 native update — 0.6.8 (25)

SLOOP is now compiled from official tag v2.8, commit
`b77bf55e3bf804665b8f5dffb5955bd8443311f0`, and selected only for the
verified `fb69b4311790eb7ec09498be16ae2b71bd681840e221c0d8cfdb26fb5f9a2928`
package. The new persisted FX FADE setting is restored by the host adapter.

Exact 2.7.1 project/backup envelopes remain readable under 2.8. Musical project
overlays adopt the current engine identity and preserve current settings. When
2.8 has no autosave, the loader copies bytes from a verified 2.7.1 predecessor,
preferably the remembered workspace, and restores them into a disposable
candidate before writing a separate 2.8 autosave. Original packages, autosaves,
and named files remain unchanged. Ambiguous predecessors and damaged sizes fail
explicitly. Other firmware hashes are not accepted as compatible.

Host release workspace: 87 passed. Actual old/new C-engine probes retain all 12
logical objects, A–D, settings and four sample regions; old fixture is untouched.
Upstream 2.8 UI suite includes new NOTES/drum editing and 20,000-frame fuzz.
Simulator validation and TestFlight distribution receipt:
`Research/Sloop25/verification.json`. Physical phone acceptance is separate.

0.6.8 (25) upload completed after owner re-added Apple Account in Xcode. Apple
processed build88194d0e-23d4-4e8e-8779-4047d6963a16; What to Test saved; only
Owner Beta (Internal,1tester) assigned. Final iOS Builds readback: Testing,
Owner Beta,1invitation. Screenshot: Research/Sloop25/testflight-testing.png.
API service activation and Developer-key creation were separately owner-approved;
private file retrieval is pending manual Chrome download. API authentication is
not claimed verified. No public release or physical-phone acceptance claimed.
