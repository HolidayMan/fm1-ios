# Mac WebKit/WASM binary-engine experiment — 2026-10-18

The same upstream WASM engine loaded Stock V15, Felucca 1.6.1 and SLOOP 2.7.1
FWSC binaries inside a real native macOS WKWebView. No firmware-specific source
engine was used. The measured SLOOP heavy cases did not reach real time, including
a fresh AC-powered, Low-Power-Mode-off foreground run. The primary project stayed
stable for 120 guest seconds at 0.663× warm realtime. iPhone performance remains
unverified.

All experiment source, binaries, synthetic flash, raw RAM, metrics and logs are
local under ignored `Research/WebKitPoC` and `Research/WebKitWorkloads`. Stable
App, Vendor, Core sources and retained app/core archives were not changed by this
experiment. No phone, Software Factory, signing/delivery or publication occurred.

## Host and shared engine

- Apple M1 Pro, 10 cores, 16 GiB; macOS 27.0.1 (26A434), AC power, battery charged.
- Apple Swift 6.4; native AppKit/WKWebView harness, ephemeral website data store.
- Upstream `fm1-emu` revision `7ca5b96c9e828dea5176fc60f0b945abbf442895`.
- The research module SHA-256 is
  `52680cf8d09566f13c12c5090a7993afc5509291f452cd134f49af8a5f802a88`.
  It adds only full-flash restore/export and read-only RAM visibility to a copied
  research source tree. The pi32v2-to-WASM translator is upstream's implementation.
- Guest frequency stays 240 MHz; output is 44.1 kHz, stereo, 128-frame quanta.
  No lowered guest clock is used to improve the reported ratio.
- Local origin `http://127.0.0.1:8763`, secure context. COOP/COEP enables isolation
  for final Worker runs. Actual fetched package/module hashes are recorded.

The initial paced AudioWorklet baseline predates the final read-only observability
exports and module-hash receipt. It uses the same pinned upstream translator
source; the final Worker/Node comparisons share the exact module hash above.

The actual WK probe found WebAssembly and AudioWorklet available at this origin.
AudioWorklet has no `performance` object; its clock is integer-millisecond
`Date.now`. Worker `performance.now` measured an approximately 0.02 ms minimum
step with isolation. A file-origin, blob-module capability probe failed CORS;
this is not a claim that every possible file-origin arrangement is impossible.

## Actual AudioWorklet baseline

Each fresh binary ran a ten-guest-second chord scenario with upstream's cap of
16 synchronous region compilations per render. The warm interval starts at
three guest seconds. The upstream 30 Hz LCD/LED copying/messages remain; the
page does not draw the LCD. Samples are delivered to the audio graph with zero
gain, so this was not a listening test.

| FWSC | Useful audio / wall, whole run | Warm useful audio / wall | Warm render p50/p95/p99/max, ms | Compiled regions |
|---|---:|---:|---|---:|
| Stock V15 | 0.976× | 0.996× | 1 / 3 / 5 / 7 | 1,044 |
| Felucca 1.6.1 | 0.989× | 1.000× | 2 / 2 / 3 / 3 | 907 |
| SLOOP 2.7.1 | 0.988× | 1.000× | 1 / 4 / 4 / 5 | 606 |

The callback budget is 2.9025 ms. Stock's cold maximum was 82 ms, whereas an
individual synchronous dynamic-module compile was at most 2 ms: WASM compilation
alone does not account for the full translation/decoding/render spike. These
coarse deadline-overrun counters are proxies, not physical audio-dropout counts.
Whole-run 5–7 short quanta include boot before audio starts. Early baseline
reports predate separate warm shortage counters. The first Stock/JIT trial also
overlapped a brief research WASM build, so it is a preliminary baseline.

Paced throughput near 1× means the audio device paced the machine; it does not
show CPU headroom. Browser-reported base latency was 2.9025 ms and output latency
was zero; neither establishes input-to-speaker or acoustic latency.

## Heavy actual WebKit Worker measurements

The same module then ran unpaced in a real WK WebWorker. These runs use no
artificial timer yields. Each has 20 guest seconds; PLAY starts at 5 seconds,
repeated drum-pad input at 10 seconds, and the reported warm interval is 15–20
guest seconds. Each fixture restores exactly one MiB of synthetic flash before
the first instruction, then exports and compares every byte.

All fixtures configure four tracks of 64 filled steps, 240 BPM, 1/32 subdivision,
ratchet ×4, microtiming, parameter locks and multiple effects. Configured voice
budgets are nominally eight shared synth voices, six drums and twelve grains.
These settings do not prove an absolute runtime cap or simultaneous peak DSP.
SNAP/WHITE are keyboard/pitch quantization modes; REC timing QUANT and arbitrary
recording workflows were not separately validated.

| Synthetic project | Warm useful audio / wall | Warm render p95 / p99 / max, ms | Regions compiled | Warm missing frames |
|---|---:|---|---:|---:|
| FM6 / PHYS / GRAIN | 0.674× | 9.38 / 9.98 / 11.48 | 2,774 | 0 |
| Three FM6 parts | 0.792× | 8.08 / 8.54 / 9.86 | 2,356 | 0 |
| FM6 / NOISE / GRAIN | 0.750× | 8.64 / 9.38 / 10.34 | 2,600 | 0 |
| Mixed, keyboard/pitch SNAP | 0.636× | 10.20 / 10.88 / 13.22 | 2,812 | 0 |
| Mixed, keyboard/pitch WHITE | 0.640× | 10.10 / 10.68 / 12.02 | 2,851 | 0 |

Each reached its full 20-second guest target, produced signal and a multicolor
LCD, passed full flash roundtrip, and had five boot short quanta followed by zero
warm core shortages. Wall times were 22.895–26.859 seconds. Using summed
render-call wall time instead of full run wall time changes these bounded ratios
by less than 0.001×; neither clock is a thread CPU-time measurement.

Binary validity was checked by read-only RAM observations. All five snapshots
uniquely match the four contiguous runtime tracks using their immutable step
patterns, stride, engines and lengths. A separate first-fixture sequence at
5.204, 10.002 and 12.004 seconds shows eight active synth voices (4+2+2), all four
tracks with 64 steps, advancing absolute step 6→159→224 and pass 1→3→4. This is
actual FWSC execution evidence, separate from a source-native observer. Drums
and grain activity/caps were not independently resolved from this binary RAM.
The SNAP/WHITE snapshots contain ten/eleven live synth `active` flags respectively;
they are not capped to eight in the report. Source-level repeated-note allocation
offers a possible explanation, but neither an emulator defect nor the audible
simultaneous voice maximum is established by that observation.

The Mac became locked during the initial baseline. Unmodified WK host trials
then suspended. Keeping a public native `callAsyncJavaScript` request outstanding
allowed bounded locked-session execution, but longer trials degraded after about
30 wall seconds, including a no-yield trial. Thermal/performance warnings were
not recorded by `pmset`; system free-memory percentage was 52%, and no other
benchmark/build was running. These facts do not identify the cause or remove the
background scheduling confound. Longer trials are retained privately but excluded
from the table. These locked-session results alone cannot certify sustained
foreground performance; the later unlocked AC rerun below addresses that host
condition. Neither table is an iPhone measurement.

The bounded interpreter comparison reached roughly fourteen guest seconds
before its wall cap, then exposed a harness JSON error for non-finite empty-warm
metrics. That writer has been fixed. This failure is not a firmware crash or a
valid complete warm interpreter result.

A bare native JavaScriptCore JSContext was also probed. It supports WebAssembly,
but a sampled Stock run executed through JSC's IPInt/low-level interpreter path
and yielded approximately 0.048× useful audio/wall. That distinct context is not
used as a WKWebView performance substitute.

## Distinct Node/V8 comparison and fixed corpus

The identical WASM, SLOOP package, synthetic flash and input schedule ran in
Node 26.0.0 / V8 14.6.202.33-node.19. The primary heavy case completed 30.004
guest seconds in 39.860 wall seconds. Its warm useful-audio ratio was 0.693×,
with zero warm missing frames. Five-second windows at 15–20, 20–25 and 25–30
guest seconds yielded 0.670×, 0.703× and 0.708×. This distinct context did not
show the late collapse seen in longer locked WK runs; it does not establish
foreground WK or iPhone performance. It also failed the measured heavy real-time
goal on this Mac.

All 53 hash-pinned catalogue FWSC files were then tested serially with the same
WASM and an eight-guest-second generic note script (27-key hold at 5–7 seconds
and release; queued cycling after 8.5 seconds is outside this measurement).
This is Node/V8 coverage, not 53-package WK acceptance:

| Observation | Packages |
|---|---:|
| Accepted by FWSC loader | 53 / 53 |
| Reached eight guest seconds without an emulator halt | 52 / 53 |
| Produced actual audio frames and a multicolor LCD | 51 / 53 |
| Produced nonzero audio in the 5–8 second input interval | 48 / 53 |

Exceptions are recorded independently:

- **Bubba 0.7.0-beta:** zero audio frames and blank LCD. A 20-guest-second
  translator-on recheck remained blank/silent. The translator-off recheck
  reached 11.001 guest seconds at its 30-second wall cap with the same outcome.
- **Obervave 1.5:** emulator halted. The bounded translator-on and translator-off
  rechecks both halted under the same script. This does not identify whether the
  defect lies in firmware, emulated ISA/peripherals or another core behavior.
- **CTL 0.9.2, Pigeon 0.3.1, Beetle 1.01d_RC:** actual frame delivery and
  multicolor LCD, with no nonzero signal under this generic script. That is not
  sufficient to label these packages incompatible; control/patch/input needs
  were not tailored per firmware.

All 51 completed cases with actual frames had zero warm missing frames. FM106 Beta4,
HYP1 1.5.15 and Frodhes 0.9.2 still measured below 1× warm useful-audio throughput
(0.742×, 0.840×, 0.813×) in this short generic script. Boot/signal evidence does
not imply universal real-time playback or valid behavior for every control/save.

`Research/WebKitPoC/results/catalogue-summary.json` contains every exact tested
version/hash/outcome; `Research/WebKitWorkloads/compatibility/independent-node-review.json`
independently checks corpus coverage, hashes, frame conservation and import
failures. Every completed case conserved total and cold/warm frames; dynamic
module import compilation failures were zero.

## Short translator correctness comparison

Fresh Stock V15 and SLOOP 2.7.1 packages each ran the same 800/900/1000 ms chord
script with the guest translator enabled and disabled. For each package the
first 176,400 useful stereo frames (four seconds, 705,600 interleaved i16 bytes)
were captured privately and compared byte for byte. Both pairs were equal;
their final LCD fingerprints also matched. PCM SHA-256:

| Package | Matching on/off PCM prefix SHA-256 |
|---|---|
| Stock V15 | `4498caf2d91e69fb4a54d85d81faae8e3e4f3489c7fe04904d40706fafa468fe` |
| SLOOP 2.7.1 | `55004f18c294274030ff07da6385136ebaf5cb9d8d37bf3a14d7f4b3664a85b5` |

An independent reader rechecked all four PCM files and their hashes. This is
short fixed-input Node/V8 parity, not heavy-project, all-catalogue, hardware or
listening equivalence. Receipts: `results/parity-summary.json` and private PCM.

The separate binary/no-runtime-JIT comparison is documented in
[no-jit-benchmark.md](no-jit-benchmark.md). Its generic and corpus-specialized
paths have distinct scope; neither is a source-native SLOOP replacement.

## Unlocked foreground rerun — 2026-10-18, 10:10–10:14 UTC

After the owner unlocked the Mac, the five 20-guest-second Worker cases were
repeated with the same module, FWSC, synthetic projects, scripts, guest clock,
sample rate and 15-second warm boundary. The native host now records active,
visible/occluded, loginwindow, thermal and Low Power Mode state every two seconds
and on focus/occlusion changes. The one-MiB RAM observation copies were disabled
for these reruns; upstream 30 Hz LCD/LED copying remained unchanged.

Read-only preflight found ChatGPT rather than loginwindow in front. During every
post-startup observation each benchmark window was active and visible/unoccluded;
loginwindow stayed false and thermal state was nominal. However, the Mac was on
battery with **Low Power Mode enabled** throughout every case. The measured
battery policy was `lowpowermode 1`; AC policy was `0`. No power or lock preference
was changed by the experiment. A task-scoped, bounded `caffeinate -di` and explicit
host idle-display/system-sleep activity assertions kept the Mac awake.

| Heavy project | Locked-session warm ratio above | Unlocked, battery/LPM-on warm ratio |
|---|---:|---:|
| FM6 / PHYS / GRAIN | 0.674× | 0.558× |
| Three FM6 parts | 0.792× | 0.652× |
| FM6 / NOISE / GRAIN | 0.750× | 0.628× |
| Mixed, keyboard/pitch SNAP | 0.636× | 0.543× |
| Mixed, keyboard/pitch WHITE | 0.640× | 0.534× |

Every rerun reached its full guest target, restored identical flash, and had zero
warm core missing frames. The different power condition prevents attributing the
ratio change to unlocking alone, and these numbers do not establish unrestricted
host speed. Receipts: `Research/WebKitPoC/results/unlocked-five*.json`, including
the native `hostConditions` timelines.

The matched native static-768 control on battery/LPM-on completed 30.004 guest
seconds with warm useful-audio throughput 0.495425× and zero warm missing frames.
Its night result was 0.599×. Binary/input hashes, complete PCM fingerprint and
both CPU instruction totals match the night control; the power setting is a
material difference. Its receipt is
`Research/WebKitWorkloads/no-jit/run-20261018T101424Z/summary.json`, with details in
[no-jit-benchmark.md](no-jit-benchmark.md).

All hosts, the loopback server and the task's bounded sleep-prevention process
were stopped after this LPM-on stage. Receipt:
`Research/WebKitPoC/unlocked-cleanup.json`. No 120-second LPM-on run was started.

## Unlocked AC, Low Power Mode off — 2026-10-18, 10:20–10:26 UTC

After the owner connected AC, native preflight confirmed Low Power Mode off,
nominal thermal state and no foreground loginwindow. The same five-case suite,
120-guest-second primary project and paced AudioWorklet case then ran serially.
No build or other benchmark ran concurrently. Read-only process observation did
show background indexing, a browser renderer and WindowServer activity; the host
was not an otherwise idle laboratory system. Every native observation after the
first startup second reported the benchmark active, visible and unoccluded,
loginwindow false, Low Power Mode false and thermal state nominal. Periodic
observations do not prove the absence of all intervening user/system activity.

The exact module, binary, fixture, inputs, 240 MHz guest clock, 44.1 kHz output,
128-frame quantum and warm boundary match the earlier tests. As in the battery
rerun, RAM snapshot copies were disabled; 30 Hz LCD/LED copying remained enabled.
The guarded runner checks power/session before each case and never changes
preferences. Bounded `caffeinate -di` plus the native activity assertions prevented
idle sleep during this suite.

| Heavy project | AC/LPM-off warm useful audio / wall | Warm render p95 / p99 / max, ms | Regions compiled |
|---|---:|---|---:|
| FM6 / PHYS / GRAIN | 0.630× | 10.18 / 10.90 / 12.26 | 2,774 |
| Three FM6 parts | 0.727× | 8.98 / 9.90 / 11.86 | 2,356 |
| FM6 / NOISE / GRAIN | 0.705× | 9.02 / 9.84 / 23.90 | 2,600 |
| Mixed, keyboard/pitch SNAP | 0.621× | 10.18 / 11.02 / 12.78 | 2,812 |
| Mixed, keyboard/pitch WHITE | 0.624× | 10.14 / 10.86 / 12.38 | 2,851 |

All reached 20 guest seconds with zero warm core missing frames. All five were
faster than the battery/LPM-on rerun but slightly slower than the earlier bounded
locked-session numbers. Power was not captured for the night runs, so neither
unlocking nor power alone explains every difference. These are measured host
conditions, not a claim of the machine's absolute maximum speed.

The sustained primary case completed **120.004 guest seconds in 178.604 wall
seconds**, whole useful-audio ratio 0.671×, warm 15–120-second ratio **0.663×**.
Warm render p50/p95/p99/max were 0.08/9.56/10.28/16.28 ms; 4,147 regions compiled,
with zero warm core missing frames. Five-guest-second warm windows ranged from
0.626× to 0.680×; the final window was 0.675×. It did not exhibit the earlier
locked-session late collapse. This resolves that scheduling uncertainty for
this foreground run while still failing the measured real-time workload goal.

The actual paced primary AudioWorklet reached 20 guest seconds in 29.924 wall
seconds. Warm useful-audio/wall was **0.618×**, with render p50/p95/p99/max of
1/10/11/12 ms. **861 of 1,722 warm callbacks** exceeded the 2.9025 ms budget by
its coarse timer. Warm core missing frames were zero: the emulator supplied its
requested frames when called, but callbacks themselves ran too slowly. These
Date.now-quantized overruns are deadline proxies, not measured device underruns
or physical dropout counts. The graph still used zero gain; audible quality and
input-to-speaker latency were not measured. Buffering alone cannot supply the
missing average compute throughput demonstrated here.

Fresh configurations, native condition timelines, results and owned-process
cleanup are under `Research/WebKitPoC/results/no-lpm-20261018T102003Z-*`.
The master receipt is `no-lpm-20261018T102003Z-run.json`. Reproduction command:

```sh
python3 Research/WebKitPoC/run-no-lpm.py
```

## Separate helper-frequency profile

After the timing suite, one additional actual WK Worker primary-project run
used the unchanged module's profiling exports. The measured counter interval is
15.004–20.000 guest seconds. Profiling was enabled before execution; guest JIT
was initially off until CPU1 existed (209 guest ms), then enabled so both CPUs'
JIT instances captured the profiling flag. This avoids an initialization-order
limitation in the upstream profile toggle. Both CPUs returned nonzero helper
counters. Instrumentation changes execution cost; this run is excluded from
throughput comparisons.

| Counter in warm interval | CPU0 | CPU1 |
|---|---:|---:|
| Translated region entries | 27,382,603 | 50,134,703 |
| Translated instructions | 1,161,445,973 | 659,762,916 |
| Generic `h_op` fallback calls | 64,881,422 | 3,605,705 |
| Fallback calls / translated instructions | 5.586% | 0.547% |
| `FOp` fallback calls | 0 | 0 |

CPU0's leading fallback labels were `Raw21` (39,472,609), `Raw16` (8,500,180),
`Raw32` (7,717,108), `Un` (3,268,466), `SetIe` (2,119,329) and `Div` (1,596,977).
CPU1's leaders were `Raw32` (1,662,479), `Raw19` (559,716), `Raw16` (496,354) and
`Div` (323,650). These labels are upstream decoder/profile categories, not a
host CPU stack profile. Counts cover `h_op` only, excluding bus `h_read`/`h_write`
helpers; frequency does not establish time spent. This workload provides no
frequency evidence that adding floating-point emitters is its primary remedy.
Register-memory traffic and the frequent raw-operation fallbacks are candidates
for separately measured, correctness-gated universal translator experiments.

Profile harness/configuration and counters are private at
`Research/WebKitPoC/web/profile-worker.js`, `foreground-helper-profile.json`,
`results/foreground-helper-profile-000.json` and
`results/helper-profile-summary.json`. Its server and bounded awake process were
stopped afterward (`Research/WebKitPoC/profile-cleanup.json`).

## First measured translator optimization — 2026-10-18, 10:37–10:38 UTC

Two frozen research modules were compared in fresh actual WK Workers, serially,
using the same primary project, 20 guest seconds, 15-second warm boundary and
unchanged input/render harness. The candidate directly emits the paired-word
`Raw21` operation instead of calling the generic fallback. It applies to the
instruction encoding rather than a firmware address or SLOOP-specific function.
The original research module was retained unchanged; each case fetched a distinct
asset and verified its actual byte hash before boot.

| Module | Warm useful audio / wall | Warm render p95 / p99 / max, ms |
|---|---:|---|
| Fresh rebuilt baseline (`baseline2`) | 0.628× | 10.22 / 11.06 / 13.00 |
| Raw21 paired-word emitter (`pair`) | 0.686× | 9.30 / 9.90 / 10.92 |

This matched pair improved warm throughput by **9.24%** on this WebKit run, but
still did not reach realtime. Both completed 20 guest seconds, produced 874,368
actual frames, compiled 2,774 regions, passed flash roundtrip, and had zero warm
missing frames (five initial short quanta). AC power was confirmed; all native
observations after the first startup second were active, visible/unoccluded,
loginwindow false, Low Power Mode off and thermal nominal. One ordered pair
establishes this observed gain, not a statistically isolated universal speedup.
No sustained or paced acceptance is inferred for this candidate.

Actual fetched SHA-256:

- Baseline: `ef74dc04f0715ad4d21b9ccf8397546a4bf55116f3b895ef8d5783140c553054`.
- Candidate: `bf724783b4d7a0cf8a779e1b615b763ecf9a61323541f1e8988831e8168f8d14`.

The separate optimization work has instruction-oracle and full heavy-interval
PCM/state comparisons; this timing pair adds actual WebKit performance evidence.
Private exact configuration, fetched hashes, condition timelines and cleanup:
`Research/WebKitPoC/raw21-wk-ab.json`, `results/raw21-wk-ab-000.json`,
`results/raw21-wk-ab-001.json`, `results/raw21-wk-summary.json` and
`results/raw21-wk-run.json`. No stable app/core code or archive was changed.

## Final bounded combined optimization — 2026-10-18, 10:40–10:42 UTC

The next frozen candidate combines the Raw21 emitter with direct lowering of
selected Raw16/Raw32 memory operations. It was compared with a fresh rebuilt
baseline in the same actual WK Worker primary-project test (20 guest seconds,
warm 15–20 seconds), with per-case fetched-byte checks and no simultaneous build
or benchmark.

| Module | Warm useful audio / wall | Warm render p95 / p99 / max, ms |
|---|---:|---|
| Fresh rebuilt baseline (`baseline3`) | 0.628× | 10.18 / 11.00 / 24.86 |
| Combined paired-word/memory emitter (`pair-mem`) | 0.711× | 9.02 / 9.52 / 10.26 |

The combined candidate improved warm throughput by approximately 13% against its
matched baseline in this run. This remains below realtime. Its comparison with
the prior candidate is across different ordered pairs, so the incremental memory
emitter benefit is not isolated by this measurement. The baseline's maximum is
an individual outlier; the percentile and average metrics also improved. No
additional sustained or paced run was undertaken for this sub-realtime candidate.

Both cases reached 20 guest seconds, produced 874,368 frames, compiled 2,774
regions, passed flash roundtrip, and had zero warm missing frames. Native
post-startup conditions stayed active, visible/unoccluded, loginwindow false,
Low Power Mode off and thermal nominal; the Mac was on AC power. These remain
one-pair host observations, not a universal performance or acoustic claim.

Actual fetched SHA-256:

- Baseline: `505c3d897b0d31ca65fd1f608dfee9b7e1fea059d2a7081778d1385927f41646`.
- Candidate: `fe0d28751137bd4abe8b4c67a369acb8d1aaf8500f4cc890986fe91d3b158fb0`.

Exact private receipts are `Research/WebKitPoC/results/raw21-mem-wk-ab-000.json`,
`raw21-mem-wk-ab-001.json`, `raw21-mem-wk-summary.json` and
`raw21-mem-wk-run.json`. Owned server and sleep-prevention processes were stopped.
The optimization design and separate correctness gates are documented in
[universal-acceleration.md](universal-acceleration.md). The original 52680 research
module and stable app/core archives remain unchanged.

## Corrected region deduplication follow-up

With the same paired-word/memory lowering, preserving the original full region
discovery before omitting already translated bodies improves an actual macOS
WKWebView pair from **0.694× to 0.787×** warm throughput (+13.28%). Warm render
p95/p99 changes from 9.38/10.04 ms to 7.90/8.30 ms; maximum changes from 10.88
to 19.88 ms. This is still below real time, with an unresolved maximum outlier.
Both 20-guest-second cases return 874,368 frames and report zero warm core
shortages, which is not proof of audio deadlines.

The Mac is unlocked, on AC power, Low Power Mode off, thermal state nominal.
Candidate activation/visibility is stable after startup; the baseline briefly
loses activation before warmup completes while remaining visible. Actual fetched
bytes match frozen baseline `e7f4a456…` and candidate `6551d0d8…`. Separate
Node/V8 runs compare the complete captured PCM, RAM/LCD/flash, selected CPU
fields/counts and raw exact event/audio phase byte for byte. Independent review
found no blocking defect. See [universal-acceleration.md](universal-acceleration.md)
for the rejected early-pruning variant and the corrected candidate's limits.

The same accepted corrected-deduplication module completes a subsequent
120-guest-second throughput run: warm 15–120 **0.796849×**, render p95/p99/max
7.82/8.30/15.42 ms, 5,286,272 returned frames, 4,147 compiled regions and zero
warm core shortages. All 75 condition samples after the first second (78 total) remain
active/visible/unlocked with Low Power Mode off and nominal thermal state;
AC power and actual module bytes are verified. Five-second windows stay near
0.8× throughout. This rules out an observed late warmup recovery on the tested
run; it remains below real time and is not an audio deadline or iPhone pass.
No matched percentage gain against historical 120-second runs is claimed.

## Reproduction and limits

Exact build and serial-run commands are in the private
`Research/WebKitPoC/README.md`. Primary configurations/results:

- `baseline.json` / `results/baseline-000.json` through `002.json`: paced cases.
- `heavy-bounded.json` / `results/heavy-summary.json`: bounded Worker cases.
- `results/*-12000.ram` or adjacent timestamped RAM and `*.observed.json`: private
  binary observation receipts; exact filenames include the actual guest boundary.
- `../WebKitWorkloads/manifest.json`: package/flash/input hashes, valid save CRCs,
  project checksums, source-based fixture construction and input schedules.

Results establish the tested inputs and runtime states only. A fixed catalogue
is not every firmware, release, patch, save, ISA use or peripheral path. Useful
audio frames, guest clock, core starvation, OS scheduling, audible quality,
input/output latency and human acceptance remain separate. No App Store or
universal real-time claim follows from this experiment.
