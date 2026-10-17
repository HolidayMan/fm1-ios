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
