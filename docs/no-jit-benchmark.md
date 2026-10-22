# Existing no-JIT binary interpreter comparison — 2026-10-18

The best existing no-runtime-JIT implementation tested here produced **0.599×
real time** on the mixed SLOOP workload on this Mac. The generic predecoded
threaded interpreter produced **0.545×**. Neither met real time for this workload;
these measurements do not establish iPhone performance.

The experiment ran in ignored `Research/WebKitWorkloads/no-jit`. It did not
change the app, Core/Vendor sources, frozen archives, phone or owner saves. The
CLI depends on the binary CPU/SoC emulator only; it never links source-native
SLOOP. It boots the actual SLOOP 2.7.1 FWSC, restores the isolated valid synthetic
flash before the first instruction, and uses the same input script as the WebKit
experiment. Package SHA-256 begins `7c9d269d15d1c1a4`; mixed flash SHA-256 begins
`ff7985162196490c`. Full input and executable hashes are in the private receipts.

## Matched workload and measured result

Host: Apple M1 Pro, arm64 macOS 27.0.1; Rust 1.97.0-nightly
(`9eb3be26b`, 2026-05-18), optimized release with LTO. Builds and measurements were
serialized with the WebKit experiment. Each mode used a fresh process, the same
240 MHz guest clock, actual package/flash/script, 128-frame rendering at 44.1 kHz,
and the same 4.8-million-instruction budget as the web ABI. PLAY occurs at 5 seconds,
repeated pad input starts at 10 seconds, and warm measurement starts at 15 seconds.
Each primary case reached 30.004 seconds of guest time.

| Existing implementation | Warm actual audio / wall time | Warm audio / render-call wall time | Warm missing frames | Runtime JIT entries |
|---|---:|---:|---:|---:|
| Rust cached blocks | 0.529× | 0.529× | 0 | 0 + 0 |
| Generic predecoded / computed-goto interpreter | 0.545× | 0.546× | 0 | 0 + 0 |
| Existing 768 build-time static kernels plus interpreter fallback | 0.599× | 0.599× | 0 | 0 + 0 |

Each warm interval delivered the same 661,760 real audio frames. The full runs
also had identical counts and fingerprints: 1,315,712 real frames, 640 startup
missing frames, full PCM FNV-64 `3e7dee70620791f4`, and CPU0/CPU1 retired
instruction counts (6,859,688,844 / 3,523,120,180). Profiling was disabled. Raw PCM
was not retained for these native cases; this is fingerprint agreement rather
than an independent byte comparison. This agreement
supports this workload comparison; it is not an exhaustive emulator correctness
or sound-parity proof. Zero missing frames in an unpaced run does not establish
real-time playback: these modes took more wall time than the audio they produced.

The generic threaded mode was explicitly enabled with
`FM1_THREADED_EXPERIMENT=1` in a build containing no static kernels. It decodes
firmware instructions into data/micro-operations and executes existing compiled
handlers. It generates no executable host code. The cached-block mode disabled
threaded dispatch with `FM1_NO_THREADED=1`. All CPU instances set `jit_on=false`.

The static mode uses the already-existing, verified 768-kernel manifest, with
firmware/code-pattern-specific build-time specializations and exact-match checks.
Unmatched code retains interpreter fallback. Its speed is not a universal
arbitrary-package performance guarantee. No new specialization or algorithmic
optimization was introduced for this comparison.

## Actual binary activation and bounded follow-up

Read-only guest RAM observations independently found one unique contiguous
runtime track array in every native case. All four tracks retained 64 filled
steps. Across the primary warm/final snapshots, each track's sequencer counter
advanced 320→800 and loop pass 6→13. The three synth tracks had 4/2/2 active
non-fading voice flags. These observations came from actual binary execution,
not the source-native SLOOP test backend.

One additional bounded case used the static-kernel mode and the valid WHITE
keyboard-quantization flash, with dense keyboard chords and repeated pad input.
It reached 20.000 seconds guest time; its 15-second-and-later warm interval
produced **0.595×** real time, with zero warm missing frames and zero runtime JIT
entries. Its receipt is
`Research/WebKitWorkloads/no-jit/run-20261018T015131Z/summary.json`.

WHITE's actual native RAM showed 6/2/3 active non-fading synth voice flags, or 11
total, at both warm/final observations. This agrees with the WebKit observation
that dense legitimate input can exceed the source's nominal shared budget of
eight. The source's same-note allocation shortcut can revive fading voices
without another budget check; that is a plausible explanation, not a separately
proved firmware defect. Report the configured budget and observed activity
separately. These counts neither prove independently audible voices nor establish
a universal maximum. The WHITE result also confirms this observation is not
exclusive to WebAssembly/JIT execution.

## Boundaries and reproduction

The harness avoids per-event screenshots, disk writes, raw audio storage and
instruction profiling in the measured loop. It includes audio draining, normalized
float signal checks and a PCM fingerprint. Render-only time is separately
reported. It copies warm/final guest RAM for activation checks, and writes files
after the timed interval. The fixed warm-start RAM copy occurs before the warm
timer starts.

Both routes derive from the same pinned upstream revision
`7ca5b96c9e828dea5176fc60f0b945abbf442895`. This native route includes the
already-existing local Vendor optimizations and C dispatch/static paths, while
WebKit uses the upstream engine. It is **not a clean JIT on/off ablation**:
implementation optimizations, runtime and scheduling differ. Earlier WebKit
diagnostic runs included explicit timer yields; the final bounded
WebKit table uses no artificial yields, matching this native scheduling policy.
Warm phase starts are matched at 15 seconds. The native primary cases measure
15–30 seconds; the final bounded WebKit cases measure 15–20 seconds. Their
window lengths and host execution contexts therefore differ. Neither comparison proves universal hardware
maximum load, physical latency, callback reliability, long-session thermals or
listening acceptance.

Private reproduction, from the repository root, in an otherwise uncontended
benchmark window:

```sh
python3 Research/WebKitWorkloads/no-jit/build.py
python3 Research/WebKitWorkloads/no-jit/run.py
```

Both builds use separate targets under the ignored experiment directory. The
first primary measurement receipt is
`Research/WebKitWorkloads/no-jit/run-20261018T014828Z/summary.json`;
`build-receipts.json` records source, kernel and executable hashes. The workload
manifest, flash checksum checks, saved-project decoding and binary-RAM observer
are in `Research/WebKitWorkloads`.

## Unlocked-session control with Low Power Mode on — 2026-10-18

After the user unlocked the Mac, one fresh primary case reran the existing
static768 executable, with no rebuild or changed package, flash, input schedule
or emulator clock. It ran after the foreground WebKit batch released the
performance slot; no other benchmark or build ran concurrently.

The Mac was drawing battery power at 100% charge and discharging. The current
power policy reported `lowpowermode 1` immediately before and after the run.
`pmset` reported no recorded thermal or performance warning; that does not prove
unrestricted clocks or maximum available performance. The earlier native run did
not record its power mode, so this is not a controlled causal test of unlocking.

| Static768 primary control | Earlier night measurement | Unlocked session, LPM on |
|---|---:|---:|
| Warm useful audio / wall time | 0.599019× | 0.495425× |
| Warm useful audio / summed render-call wall time | 0.599111× | 0.495501× |
| Whole measured wall time | 45.612 s | 54.965 s |
| Warm measured wall time | 25.051 s | 30.289 s |
| Warm missing frames | 0 | 0 |
| Runtime JIT entries, CPU0 + CPU1 | 0 + 0 | 0 + 0 |

Both cases reached 30.004 guest seconds, with the warm interval starting at
15.004 seconds. The new control delivered the same 1,315,712 total and 661,760
warm real frames, the same 640 startup missing frames, identical full PCM
FNV-64 and retired instruction totals. Actual binary RAM again showed four
64-step tracks, synth voice flags 4/2/2, absolute step 320→800 and loop pass
6→13. These checks support a comparison of the same executed workload.

The LPM-on control was approximately 17.3% slower than the earlier measurement
and remained below real time. This does not establish a speed loss caused by
unlocking, nor the Mac's full-power speed. The path remains corpus/code-pattern
specific and is not physical-device or universal real-time acceptance.

Private receipt:
`Research/WebKitWorkloads/no-jit/run-20261018T101424Z/summary.json`, with before/
after power-policy receipts, actual guest RAM observations and
`independent-validation.json`. The cached executable SHA-256 remained
`43a29f0112113e3a7768d32fdc6deffd2ee4cc4f2fd5a7ff0a8a5410d39fd7f9`.
