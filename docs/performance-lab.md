# Local performance lab

Private fixtures, flash snapshots, raw test logs and detailed reports stay under ignored `Research/` or `build/`. The runner only uses the explicitly supplied dedicated FM1 simulator; it contains no physical-device commands. Physical iPhone firmware and saves are untouched.

## Baseline: retained core at 70b25ce

Release Rust `aarch64-apple-ios-sim` plus a Release native app/test bundle (`ENABLE_TESTABILITY=YES`), on the dedicated **FM1 • iPhone 12** simulator, iOS 27.0. Host: M1 Pro, 10 CPU cores. The simulator runs on the Mac CPU; it does not reproduce A14 timing. Each unchanged scenario holds matrix key 21 for 25 seconds after start, then pauses. No warmup or metric reset was added to this comparison.

All three measurement tests passed. Passing the harness is not a real-time quality pass.

| Firmware | Simulator mean / recent p95 render budget | Simulator missing / requested output frames | Simulator shortage | Physical iPhone 12 mean / p95 | Physical shortage |
|---|---:|---:|---:|---:|---:|
| Stock V15 | 47.36% / 52.76% | 512 / 1,144,320 | 0.045% | 47.67% / 63.97% | 0.062% |
| Felucca 1.6.1 | 112.09% / 119.46% | 135,168 / 1,122,816 | 12.04% | 130.56% / 138.13% | 24.24% |
| SLOOP 2.7.1 | 109.23% / 116.93% | 128,000 / 1,147,392 | 11.16% | 121.50% / 129.80% | 19.54% |

A render ratio of 100% means emulator rendering consumes the entire duration of the audio being produced. Both heavier firmwares exceed that limit and show substantial ring shortages on the simulator, so this environment reproduces the problem and is useful for profiling and candidate comparisons. Its absolute numbers are not predictions of physical-phone performance.

Core missing frames were separately 0 / 3,072 / 3,072 for Stock / Felucca / SLOOP; the much larger output shortages are a different counter. These runs include firmware startup. Ring underflows count unavailable samples at source callbacks; they do not measure OS/hardware missed callbacks, perceived clicks or touch-to-sound latency.

The simulator reported a **44.1 kHz hardware/output route**, while the prior physical iPhone 12 reference used a **48 kHz route**; the firmware/source stream is 44.1 kHz in both. The physical reference used the source ring and retained safe core before the final metadata-cache bounds/describe and import/UI edits. Firmware binaries match the pinned releases; saved patch state was not synchronized between the physical and simulated devices. Use these measurements to establish qualitative reproduction; compare optimization candidates against repeated simulator baselines from identical saved-state fixtures.

Private receipts:

- `build/PerformanceSimulator-baseline-70b25ce/Baseline.xcresult`.
- `Research/Performance/simulator-baseline-70b25ce-{stock,felucca,sloop}.json`.
- `Research/Performance/simulator-baseline-70b25ce-comparison.json`.
- `Research/Performance/simulator-baseline-70b25ce-manifest.json` records frozen archive/app hashes.

## Final candidate: RAM fallback, 0.2.1 (4)

The final variant retains the 768 guarded XIP kernels and sends RAM execution through the original Rust interpreter. Its frozen simulator archive SHA-256 is `7a54c09eeb1e3ddd47b74fa058aca0c4a482bf21d2d44618f2ef99e0ee203cfd`. The exact final source/header receipt and archive/app/test hashes are recorded in `build/PerformanceSimulator-aot-final-4/performance-build.json`. No PGO profile is used.

Three final Release stress scenarios passed on the dedicated simulator, using the same restored package/flash snapshot as the intermediate run. Each had five seconds of warmup followed by three measured 20-second phases. Every phase delivered 20 retrigger cycles, with 140 key releases/140 attacks and 160 encoder events per complete scenario. All phases had zero additional output-underrun frames/callbacks and zero missing core frames; mean ≤0.8 and recent p95 <1 flags were true throughout.

| Firmware | Final simulator steady mean / recent p95 | Simulator missing / requested output | Final physical iPhone 12 steady mean / recent p95 | Physical missing / requested output |
| --- | ---: | ---: | ---: | ---: |
| Stock | 0.579607 / 0.851624 | 0 / 2,646,528 | 0.587516 / 0.930884 | 0 / 2,646,441 |
| Felucca | 0.586219 / 0.625848 | 0 / 2,646,528 | 0.581758 / 0.635018 | 0 / 2,646,441 |
| SLOOP | 0.596570 / 0.631633 | 0 / 2,646,528 | 0.607138 / 0.637490 | 0 / 2,646,882 |

Stock's final simulator phase means were 0.540945 / 0.602304 / 0.595570, with recent p95 0.786152 / 0.779233 / 0.851624. Its prior intermediate steady mean/p95 were 0.672291/0.962958. The physical Stock mean/p95 also improved from 0.694650/1.016981 to 0.587516/0.930884; physical input package and starting flash hashes matched between those two runs. These are finite workload observations, not a guarantee for every patch or arbitrary polyphony.

The physical results were collected by the parent task and verified here from local `Research/Performance/physical-aot-final-build4/` reports; this simulator runner performed no physical-device actions. Every physical phase likewise had zero shortages and favorable mean/p95 flags. Physical Stock ended in thermal state 1 (fair), while physical Felucca/SLOOP and all simulator cases ended nominal (0). Low Power Mode was false throughout. Simulator hardware/source rates were 44.1/44.1 kHz; physical hardware/source rates were 48/44.1 kHz. The Mac controller for the concurrent physical XCTest remained active, but host builds and emulator benchmarks were stopped during simulator measurement. Simulator timing is not an A14 speed model.

Startup counters were retained separately and excluded from steady windows. Final simulator Stock warmup contained 512 missing output frames; Felucca/SLOOP warmup each contained 3,072 missing core frames. No original 25-second comparison or broad UI/unit suite was repeated for this final guard-only variant; the build-3 evidence below remains explicitly intermediate. Final core correctness/sanitizer evidence is recorded separately by its owner.

The complete final simulator runner exited 0. It re-resolved XCTest's current app container, validated all run/firmware/package/initial-flash pins, shut down the dedicated simulator, and restored previous package/save files. Every restored target was then checked byte-for-byte against its backup. Private receipts: `Research/Performance/aot-final-stress-4/{summary,stock,felucca,sloop}.json` and `build/PerformanceSimulator-aot-final-4/aot-final-stress-4.xcresult`.

## Intermediate static-kernel candidate: 0.2.1 (3)

The candidate uses 768 guarded static kernels and a frozen Release simulator archive with SHA-256 `6949627c8f5f36706a969481b25fc3eda6a7c3f4560e2b681e3136a7a423d7b6`. `build/PerformanceSimulator-aot-0253/performance-build.json` records the exact archive/app/test hashes and the final core source/header receipt. The app is 0.2.1 (3); source revision remains 70b25ce plus the recorded uncommitted candidate changes. No PGO profile is linked. The same dedicated iPhone 12 simulator, original saved-state snapshot and fixed firmware hashes were used. Other builds/profilers were stopped during measurement, with 45 seconds of settling after each boot/install.

All three original 25-second tests passed:

| Firmware | Mean / recent p95 ratio | Missing / requested output frames | Core missing frames |
| --- | ---: | ---: | ---: |
| Stock | 0.568586 / 0.524043 | 0 / 1,145,344 | 0 |
| Felucca | 0.574019 / 0.617235 | 0 / 1,131,520 | 3,072 |
| SLOOP | 0.584455 / 0.639400 | 0 / 1,146,368 | 3,072 |

Felucca and SLOOP mean ratios fell approximately 48.8% and 46.5% versus the original simulator baseline, with output shortages removed in these runs. **Stock's mean increased about 20.1%**, although its recent p95 was nearly unchanged; its maximum render ratio was 6.884958. This result must not be described as a universal speedup. The startup-inclusive mean and recent percentile cover different intervals, and the available observations do not establish the cause of that Stock result.

Three separate 5-second-warmup +60-second stress tests then passed. Each phase performed 20 retrigger cycles; all phases together dispatched 140 key-up and 140 key-down events per firmware, and the final phase dispatched 160 encoder events. Every phase had zero additional output-underrun frames/callbacks and zero missing core frames, with requested-output coverage close to 100%.

| Firmware | Steady mean / recent p95 at end | Missing / requested steady output frames | Single / three-key / encoder phase mean |
| --- | ---: | ---: | ---: |
| Stock | 0.672291 / 0.962958 | 0 / 2,646,528 | 0.616192 / 0.708439 / 0.692240 |
| Felucca | 0.589056 / 0.630542 | 0 / 2,646,528 | 0.599817 / 0.580902 / 0.586449 |
| SLOOP | 0.602693 / 0.667784 | 0 / 2,646,528 | 0.601430 / 0.602545 / 0.604102 |

**Stock has limited percentile headroom:** the three-key phase ended at recent p95 0.990359; the single-key and encoder phases ended at 0.906867 and 0.962958. Its warmup contained 512 output-missing frames, which were correctly excluded from steady deltas. Felucca/SLOOP's known 3,072 initial missing core frames were likewise excluded. Mean ≤0.8 and recent p95 <1 were satisfied in every measured phase, but these results do not establish a large safety margin for Stock. There is no prior baseline stress run with repeated attacks, so the increased stress load cannot be attributed to AOT from this evidence alone.

All new reports recorded Low Power Mode false, thermal state 0 (nominal), hardware/source rate 44.1 kHz. Eight ordinary checks also passed afterward: three audio-metric/smoothing, three ring-buffer, and two stress-counter arithmetic tests. Overall this targeted validation was **14 tests passed, zero failures** (three comparisons, three stress scenarios, eight ordinary checks); it was not a broad UI rerun or a physical-device/listening acceptance test.

The first complete runner comparison exposed an XCTest behavior: reinstalling during `test-without-building` relocated the app data container. The three measured cases succeeded, but the runner's original path became stale during report collection/restore. Reports were recovered from the current container identified by the dedicated simulator's bundle metadata, every run/firmware/package/initial-flash pin was checked, and all prior package/save bytes were restored and verified while the simulator was shut down. The runner now resolves the current container again after testing and immediately before shutdown. The subsequent full stress-plus-diagnostics run exited 0, collected reports successfully, and restored previous simulator package/save bytes, verified against its backup. The dedicated simulator is shut down.

Private receipts:

- `Research/Performance/aot-comparison-0253/summary.json` and per-firmware reports, including the explicit recovery note.
- `Research/Performance/aot-stress-0253/summary.json`, per-firmware reports and diagnostics log.
- `build/PerformanceSimulator-aot-0253/{aot-comparison-0253,aot-stress-0253,aot-stress-0253-diagnostics}.xcresult`.

## Repeatable simulator fixture state

`Research/Performance/simulator-baseline-70b25ce-state/manifest.json` records the exact package filenames/IDs, package SHA-256 and initial flash state for this simulator. The initial Stock flash bytes were recovered after the run **only because their SHA-256 matched the original pre-run report**. The original reports explicitly recorded no flash file for Felucca or SLOOP; the snapshot therefore contains absence markers for them, not their newly created post-run saves. This reconstructs the original baseline input state without treating changed post-run bytes as original input.

The runner checks every snapshot hash, backs up the simulator's current matching package/save files, restores the recorded inputs before testing, and verifies each report's selected ID, package hash and initial flash hash. It stops the simulator before restoring its previous files, including on failure. Backups remain in the ignored run folder for recovery. Other simulator packages are left alone.

If original bytes cannot be recovered and an initial state was not explicitly absent, create a clearly named new fixture-state snapshot and rerun **both** baseline and candidate against it. A post-run state with a different hash must never be relabeled as the original baseline.

## Run

Run from the repository root. Reserve a quiet host window for measurement: no simultaneous builds, other simulators or profiling processes. The script never stops unrelated workloads for you. Ordinary simulator tests skip these 25-second scenarios; the runner explicitly sets `FM1_RUN_SIMULATOR_PERFORMANCE=1` in a generated `.xctestrun` and requires a Release build.

Prepare a new frozen candidate bundle without booting or measuring:

```sh
python3 scripts/benchmark-simulator.py CAF633C4-871C-42EA-B179-3C33DCE401E4 candidate-a --prepare-only
```

Once the host is quiet, reuse it for a new uniquely labeled run:

```sh
python3 scripts/benchmark-simulator.py CAF633C4-871C-42EA-B179-3C33DCE401E4 candidate-a-run1 \
  --reuse build/PerformanceSimulator-candidate-a
```

Repeat the original frozen baseline against the same fixture state:

```sh
python3 scripts/benchmark-simulator.py CAF633C4-871C-42EA-B179-3C33DCE401E4 baseline-repeat1 \
  --reuse build/PerformanceSimulator-baseline-70b25ce
```

Without `--reuse`, the runner builds Release Rust, freezes its archive in its own derived-data folder, builds Release app/tests, then runs the measurements. `--prepare-only` separates compilation from measurement. It waits 15 seconds after boot/install by default (`--settle-seconds` can change this); this wait does not prove complete host quiescence or thermal equilibrium. Use a new run label for every result. `--snapshot` accepts another validated local snapshot inside `Research/`, bound to that same explicit simulator UUID.

Builds/results stay under `build/PerformanceSimulator-<label>/`; per-run aggregates, logs and previous simulator-state backups stay under `Research/Performance/<run-label>/`. Reports identify simulator versus device, simulated model, build configuration, revision, package hash, starting flash hash, render ratios, core missing frames and requested/delivered/missing output frames. Frozen reuse validates both app and test executable hashes.

The baseline and candidate runs above were executed. The runner is syntax-checked, its fixture manifest is validated, and fixture restoration round-tripped in a temporary directory with prior saves, a matching package alias and an unrelated package preserved byte-for-byte. After the container-relocation fix described above, the complete stress-plus-diagnostics run succeeded and its restoration was verified.

## Separate sustained stress check

`AudioStressTests` contains separate Stock, Felucca and SLOOP methods. They skip unless `FM1_RUN_AUDIO_STRESS=1`, and require Release. They do not change the original 25-second comparison. The runner selects only these three methods when passed `--stress`; an older frozen bundle without the stress harness is rejected.

Prepare a fresh bundle, then reserve a separate quiet window of approximately four minutes:

```sh
python3 scripts/benchmark-simulator.py CAF633C4-871C-42EA-B179-3C33DCE401E4 stress-candidate --prepare-only
python3 scripts/benchmark-simulator.py CAF633C4-871C-42EA-B179-3C33DCE401E4 stress-candidate-run1 \
  --reuse build/PerformanceSimulator-stress-candidate --stress
```

For each fixed firmware:

1. Hold matrix key 21 for five seconds of warmup, then capture cumulative counters at a worker-queue boundary.
2. Measure 20 seconds with matrix key 21, releasing and retriggering it approximately every second with a 50 ms gap.
3. Add matrix keys 25 and 28, then measure 20 seconds with all three keys retriggered together at the same cadence.
4. Repeat all three matrix keys for 20 more seconds while alternating KNOB1 encoder +1/−1 at 125 ms intervals, completing a pair every 250 ms. This uses the model input path without repeated UI automation or preset/algorithm changes.

The meaning of matrix 21/25/28 depends on firmware, tuning, mode and patch. This is an input workload, not full-polyphony certification or a guarantee of particular sounding pitches/voices.

Retriggers keep new attacks present when firmware envelopes would otherwise decay. Reports record the requested cadence, per-phase retrigger cycles and key-down/key-up event counts; these are dispatched model inputs, not measured sounding voice counts. Any pending key release is closed before a phase boundary (a last gap can therefore be shorter than 50 ms), and input counts cover retriggers only (the initial holds and final cleanup are excluded). Timer scheduling is not a hard timing guarantee.

A read-only worker snapshot records each phase boundary and the overall steady interval. Reports retain `warmupEnd` and `steadyEnd` cumulative observations separately from `steadyWindow`/`phases` deltas. Startup underflows and the known initial missing core frames therefore do not enter steady gates. No waveform, firmware clock or emulator state is reset. Before another test begins, cleanup waits for pause/checkpoint completion to avoid overlapping audio-session changes.

The mean is derived from cumulative weighted work: `(endRatio × endRequestedCoreFrames − startRatio × startRequestedCoreFrames) / deltaRequestedCoreFrames`. Requested core frames are rendered plus missing frames; subtracting percentages is invalid. `recentP95AtEnd` covers the existing recent 256-buffer window and is explicitly **not a phase-wide percentile**. Two inexpensive ordinary unit tests cover warmup exclusion/weighted arithmetic and rejection of reset counters; they do not run audio.

Hard gates require **zero additional output-underrun frames/callbacks and zero missing core frames in every phase**, at least 90% requested-output clock coverage (so a stopped callback loop cannot pass merely by reporting zero shortages), at least 15 retrigger cycles with balanced releases/attacks per phase, and at least 120 of the nominal 160 encoder events. A favorable overall mean cannot conceal a failing chord/control phase. Mean ≤80% and recent p95 <100% are separately reported headroom flags, not blind failures inherited from startup. They remain useful criteria when choosing a candidate with margin.

Stress reports are written before quality assertions, so failed candidates retain diagnostic evidence. They use separate `Stress-<firmware>.json` files; the runner's summary uses the warmup-excluded steady deltas. Fixture inputs are restored before the run and previous simulator saves restored afterward, since control activity can alter flash. C counters sampled during live rendering are individually atomic, not one transaction; do not demand exact delivered+missing conservation from a live boundary snapshot.

The Release stress build and all three candidate stress scenarios passed as recorded above. `--post-diagnostics` additionally runs the eight ordinary audio/ring/stress-arithmetic tests after measured intervals and before shutdown. These gates are engineering checks, not listening acceptance or a substitute for repeating a successful candidate on the physical iPhone.

## Isolated compiler experiment at 70b25ce

Rust PGO was tested in a `/tmp` copy of 70b25ce, with separate target directories and one equal 900-block training run per Stock/Felucca/SLOOP fixture. The matching `llvm-tools-preview` profiler tool was LLVM 22.1.4, from the same Rust 1.97 nightly toolchain. Apple LLVM 21 tools were not used to merge the profiles. Native test flags were `-Ctarget-cpu=apple-a7 -Ztune-cpu=apple-a14` for both generation and use, in addition to Release opt-level 3 and LTO. The smoke program alone used six-decimal wall formatting.

Two measurement orders (baseline → tuning variants → PGO, then PGO → tune → baseline) confirmed the following host results. Times are the mean of two runs, in seconds; lower is better. They are native M1 Pro measurements, not simulator or device performance claims.

| Firmware | Host default baseline | A7 ISA / A14 tuning | Same flags + PGO | Reduction versus default |
| --- | ---: | ---: | ---: | ---: |
| Stock | 3.820889 | 3.789444 | 3.264957 | 14.55% |
| Felucca | 10.468846 | 10.490385 | 9.624135 | 8.07% |
| SLOOP | 10.148222 | 10.069807 | 9.290645 | 8.45% |

Every variant/repeat preserved the PCM/LCD/flash FNV fingerprints and complete WAV SHA-256 for each fixture. CPU tuning alone was around 1%, which is insufficient evidence of a gain. Comparing `rustc --print cfg` confirmed that `-Ztune-cpu=apple-a14` with `target-cpu=apple-a7` left reported target features unchanged; selecting a newer `target-cpu` is a separate compatibility decision.

Both iOS static-library profile-use builds compiled, but **the macOS profile did not map hot Rust symbols on either `aarch64-apple-ios-sim` or `aarch64-apple-ios`**. Each produced 509 missing-function warnings, including `Cpu::step`/`Cpu::execute`, and two hash-mismatch warnings. The same-target native build had 41 warnings for untrained paths and no hash mismatches. Therefore this profile is not an iOS PGO candidate. Target-matched training and new measurements are required; a successful compile does not establish that a profile is being used effectively.

Private evidence, raw training manifests, the merged profile, exact fixture hashes, both matrices and mapping logs are retained under ignored `Research/Performance/CompilerPGO-70b25ce/`. These artifacts must stay local. Any source change, including generated static kernels, requires fresh training.

`scripts/experiment-pgo.py` prepares a fresh native experiment without changing `scripts/build.sh`, the shipping project or shared Cargo targets:

```sh
python3 scripts/experiment-pgo.py train native-candidate \
  --stock Research/Fixtures/Stock-V15.fwsc \
  --felucca Research/Fixtures/Felucca-1.6.1.fwsc \
  --sloop Research/Catalogue/sloop.fwsc
python3 scripts/experiment-pgo.py use Research/Performance/PGO-native-candidate
```

The runner freezes input source files and fixture bytes, records revision plus content hashes, uses a matching profiler tool, trains all three equally, merges and validates the profile, and compares exact outputs with its baseline. It fails if source/compiler/fixtures/profile changed or if the use target differs; there is no non-PGO fallback. The runner itself is syntax-checked; these new commands have not been executed. The confirmed results above used the preserved standalone experiment, not this new runner.

Target-matched simulator preparation began but was paused when the static-kernel candidate showed a larger first gain. Instrumented Rust `aarch64-apple-ios-sim` compilation succeeded and the matching LLVM profiler runtime is available. Test-only opt-in hooks can reset/write profiles with `FM1_WRITE_LLVM_PROFILE=1`. `benchmark-simulator.py --rust-archive <ignored-archive> --pgo-training` prepares a private project copy with that archive and runtime, selects only the original three scenarios, sets a writable `LLVM_PROFILE_FILE`, and requires an explicitly flushed profile per firmware. The instrumented app has **not yet been linked or trained**. Normal runs leave profiler hooks disabled. The first target-matched trial must validate symbols, profile writes, warning coverage and steady output before accepting an iOS claim.

For a validated external core candidate, `--rust-archive` also freezes an archive already inside `build/` or `Research/`, avoiding a shared Rust rebuild. The app project is copied into the run's build directory so its simulator library path points directly to the frozen archive. Reuse still verifies app/test executable hashes. Every measured report includes current diagnostics' optional Low Power Mode and thermal-state fields; older physical/simulator reports predate those fields, so their environment cannot be reconstructed from absent values.
