# Full SLOOP 2.8 source-WASM research — 2026-10-21

The full pinned SLOOP C firmware wrapper compiles to a standalone WASM module
and runs in Node/V8 on this Apple M1 Pro. It includes synthesis, sequencing,
arranger, UI drawing, controls, editor objects and the complete physical 1 MiB
flash store. This experiment uses the existing source wrapper's hardware model.
It does not execute a PI32v2 firmware binary and does not use upstream's smaller
DSP-only browser preview.

No consumer-app source, signed archive, runtime choice or phone was changed.
The module and all generated source/audio/flash remain in ignored
`Research/SourceWasm28/`. This is a Mac research result; browser/iPhone timing,
audio-device underruns, hardware equivalence and arbitrary firmware support
were not tested.

## Provenance and build

Upstream SLOOP `v2.8`, commit
`b77bf55e3bf804665b8f5dffb5955bd8443311f0`, and all seven generated resource
hashes are verified against `Core/native/upstream.lock.json`. The source wrapper
is copied locally with the same checked user-sample addressing adaptations as
the native build. The source tree is unchanged.

LLVM Clang 20.1.5 targets freestanding wasm32; the installed Android NDK's
`wasm-ld` 18.0.3 links it using upstream's small memory-function shim. No new
toolchain was installed. The module is 898,743 bytes, SHA-256
`a498d730be4c672032463b88ef0881cb3bc7ad360177aeed7d7489d0a2a1dae5`.
It has no host imports and fixed 32 MiB linear memory. Each synth owns a separate
`WebAssembly.Instance`; the Apple LLVM state rewrite is not used here.

The reference executable compiles the same full wrapper, source and test
controls directly for arm64. Both builds use `-O2 -fwrapv
-fno-strict-aliasing -ffp-contract=off`. This reference is distinct from the
shipping Rust/LLVM-state-isolated archive; the comparison does not claim
bit-exact equality with every shipping or hardware execution route.

Build pins, source/helper/module hashes and compiler versions:
[`build-receipt.json`](../Research/SourceWasm28/build-receipt.json).
The private reproducible build and runs are:

```sh
python3 Research/SourceWasm28/build.py
node Research/SourceWasm28/run.mjs
node Research/SourceWasm28/run.mjs 1
node Research/SourceWasm28/run.mjs 2
node Research/SourceWasm28/run.mjs 0 prewarm
node Research/SourceWasm28/samples.mjs
```

## Measured render cost

Node 26.0.0, V8 14.6.202.33-node.19, Apple M1 Pro. Each heavy run renders
30.00018 audio seconds in 2,584 calls of 512 frames. The real-time budget for
one such call is 11.610 ms. Timing encloses the complete source render call,
including its audio-clock-driven firmware main loop and drawing. Host input,
output copying and QA observation are included separately in loop-wall results.
Native and WASM runs execute sequentially.

Speed is the median audio-time/render-wall-time ratio. Block percentiles pool
every sampled call in that row; maxima retain all outliers.

| Scenario | Repeats | Native speed | WASM speed | WASM p50 / p95, ms | WASM maximum, ms | Calls over 11.610 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FM6 / PHYS / GRAIN stress | 5 | 44.15× | 44.96× | 0.254 / 0.300 | 16.973 | 1 / 12,920 |
| Same stress + repeated notes / controls / FX | 5 | 41.41× | 41.91× | 0.271 / 0.320 | 5.577 | 0 / 12,920 |
| Three FM6 parts | 3 | 51.26× | 52.17× | 0.217 / 0.252 | 2.862 | 0 / 7,752 |
| FM6 / NOISE / GRAIN | 3 | 49.06× | 49.91× | 0.225 / 0.275 | 11.447 | 0 / 7,752 |
| NOTES editor / repeated notes, 5.004 s | 5 | 146.28× | 150.28× | 0.077 / 0.108 | 0.863 | 0 / 2,155 |
| FM6 / PHYS / GRAIN after disposable warmup | 5 | 44.41× | 45.39× | 0.250 / 0.287 | 0.445 | 0 / 12,920 |

The first un-prewarmed stress run contained a 16.973 ms call, 1.462 times its
audio budget, at block 1,878. Its cause was not isolated; it must not be attributed
definitively to JIT startup. Native also had a 12.169 ms outlier in the controls
case. These are offline wall-time observations, not measured audio-device drops.

A separate process compiled the module in 1.511 ms, initialized a disposable
instance in 4.630 ms, and rendered 5.004 audio seconds in 0.1265 wall seconds
before creating fresh measured instances. The warmup's 431 calls peaked at
3.165 ms, with no over-budget call. The subsequent 12,920 measured WASM calls
peaked at 0.445 ms. This bounded result does not prove warmup prevents future
OS or runtime stalls. Median loop-wall speed, including input/copy/QA overhead,
was 44.71× for the original mixed stress and 45.19× after warmup.

In total, 26 paired native/WASM runs rendered 655.023 audio seconds per backend,
with 56,419 measured calls per backend; the disposable warmup is additional.

## Workload and compatibility evidence

The three pre-existing synthetic 2.7.1 stress fixtures retain 240 BPM, four
populated 64-step tracks, dense chords, x4 ratchets and the requested effects.
After the first audio second, every observed mixed-stress block had four/two/two
active synth voices, six active drum voices and eight to twelve grains. The
three-FM6 variant retained the same synth/drum activity with no grains. The
configured-effect mask was `2047`; it does not prove every individual effect is
independently audible. These are demanding legal cases, not an exhaustive
maximum-cost search. The controls case additionally exercises live voice
allocation/fades, repeated physical notes and punch-in controls.

Every paired run produced byte-identical complete int32 PCM, screen pixels,
workload observations, metrics, final 1 MiB flash and all twelve logical backup
objects. Firmware audio-clock and UI-frame counts matched. Startup preserved
the source flash. Fresh WASM instances reopened every final scenario with all
twelve objects byte-identical; fresh native reopens matched too. Interleaved
separate module instances retained independent selected-track state.

The corrected UI case enters the actual 2.8 `NOTES` page, edits pitch/length/
force and the held-OCT+ sheet, and retains exact native/WASM output and reopen
results. An earlier exploratory attempt pressed notes while SEQ was still held,
so it exercised the layer instead. Its deleted lock left unused parameter bytes
that upstream clears on reload; the same normalization occurred natively.
That earlier attempt remains separately under `exploratory-notes-layer/` and is
excluded from the final results above.

All stress cases produced nonzero output in every one-second window. Mixed
stress peak was 0.27457 of PCM16 full scale, RMS 0.17784. This is signal evidence,
not listening acceptance. The PCM ABI is integer-valued: checking its float
conversion does not establish absence of internal DSP NaNs, and no independent
floating-point health claim is made.

A separate synthetic sample test imports a CRC-valid sample through the typed
API into each of USR1–4. All four slots produce identical nonzero PCM (peak
8,997 PCM16) and retain their complete 80 KiB sample region unchanged.

Private receipts:

- [Mixed stress, controls and NOTES](../Research/SourceWasm28/results.json)
- [Three FM6 parts](../Research/SourceWasm28/variant1/results.json)
- [FM6 / NOISE / GRAIN](../Research/SourceWasm28/variant2/results.json)
- [Disposable warmup and fresh instances](../Research/SourceWasm28/variant0-prewarm/results.json)
- [Four user sample slots](../Research/SourceWasm28/samples-results.json)

Per-call timing arrays, full PCM, screens, flash and objects are retained locally
beside each receipt. No module was added to the application or uploaded.
