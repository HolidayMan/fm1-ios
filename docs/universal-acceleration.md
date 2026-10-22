# Universal binary acceleration research — 2026-10-18

The isolated experiments found a small, transferable improvement in fixed-point
DSP translation, but **did not achieve real time on the tested heavy project**.
Combining existing optimizations does not multiply their gains. No product app,
phone installation, Software Factory task or owner save was changed.

“Universal” here means an optimization selected from decoded ISA/runtime guards,
with interpreter fallback, rather than firmware source or a pinned firmware hash.
It is not a performance or correctness guarantee for every possible FWSC.

## What the actual workload spends time doing

The profiled 15–20 guest-second interval of the mixed SLOOP binary workload had:

| Core | Translated instructions | Region entries | Generic-op helper calls |
|---|---:|---:|---:|
| CPU0 | 1.161 billion | 27.38 million | 64.88 million |
| CPU1 | 0.660 billion | 50.13 million | 3.61 million |

CPU0 helper calls were dominated by Raw21 wide integer operations (39.47 million,
60.84% of its helpers), Raw16 register-pair memory accesses (8.50 million), and
Raw32 indexed memory accesses (7.72 million). **Floating-point FOp count was zero
on both cores.** These are frequencies, not sampled host CPU-time attribution;
the profile counts generic-op helpers, not memory-bus helpers. Profiling was off
for timing runs.

Source: `Research/WebKitPoC/source/crates/fm1-core/src/lib.rs:2544` defines these
raw-operation semantics; `:2719` begins Raw21. The unchanged translator's
`jit_wasm.rs:423` loads each guest register from linear memory and `:1359` sends
unsupported operations through its generic executor. Its regions already contain
up to 32 blocks/384 operations, inline ordinary RAM/XIP accesses, and resolve
many calls/returns/computed jumps inside a region.

## Measured combinations

Each Node/V8 case used the same actual FWSC, isolated synthetic project, input
script, 240 MHz guest clock, 44.1 kHz output, 20 guest-second target, and warm
boundary at 15 seconds. Builds and runs were serialized. This table reports
useful audio seconds per wall second; 1.0× would be real time.

| Matched phase | Implementation | Warm throughput | Change from phase baseline |
|---|---|---:|---:|
| v1 | Baseline translator | 0.651× | — |
| v1 | Eager 16-register region cache | 0.580× | −10.9% |
| v2 | Baseline translator | 0.663× | — |
| v2 | Inline Raw21 shifts/multiply/MAC | 0.711× | +7.2% |
| v2 | Raw21 plus eager register cache | 0.657× | −0.9% |
| v3 | Baseline translator | 0.671× | — |
| v3 | Raw21 plus Raw16/32 memory lowering | 0.709× | +5.7% |

Use the baseline from the same phase. These are single bounded feasibility runs,
not confidence intervals. The combined memory lowering gave no additional clear
benefit over Raw21 alone. Eagerly loading/flushing all 16 registers is rejected as
a speed improvement for this workload. This does not test selective caching.

Separate actual macOS WKWebView Worker cases measured:

| Implementation | Warm useful audio / wall |
|---|---:|
| Baseline translator | 0.628× |
| Raw21 only | 0.686× (+9.2%) |
| Raw21 plus Raw16/32 memory lowering | 0.711× (+13.1%) |

Thus the combined candidate improved this WebKit case even though its extra
benefit was unclear in Node. The candidate still fell below real time. For the combined pair, render p95/p99 changed from 10.18/11.00 to 9.02/9.52 ms. See the [exact WebKit cases and runtime
conditions](webkit-poc.md).
Neither Node nor desktop WebKit establishes iPhone throughput.

FPU add/subtract/multiply/divide and nonfused multiply-accumulate emitters were
also implemented and correctness-tested behind a separate switch. No timed FPU
claim is made because this heavy workload did not execute those instructions.

## What was checked

All completed primary Node/V8 cases delivered the same 874,368 actual stereo frames,
with zero warm missing frames. Their **entire** PCM captures were byte-identical,
including the period after PLAY and the dense input script; this extends beyond
the earlier four-second prefix test. Final guest RAM, LCD, flash, and selected
architectural CPU fields for both cores also matched exactly. The CPU comparison
includes PC, registers, stacks, return register, flags, special registers,
interrupt enable/depth, repeat/predication state and retired instruction counts.
It excludes host caches/pointers and is not a comparison of every SoC peripheral
or pending audio-queue field.

Generated-WASM versus executor boundary tests passed with zero module compilation
failures: 2,880 cases per v1 variant, 10,512 per v2 variant and 12,204 per v3
variant. They cover region entry points, instruction budgets, helper state sync,
MMIO-triggered exits, register aliases, fixed-point shifts/multiply/accumulator
wrap, and memory ordering/width/sign cases. Floating-point edge cases include
signed zero, subnormals, infinities and multiple NaN payloads. Immediate wide
shifts have a 0–63 count field; 64/127 tests apply to register counts modulo 64.

The initial synthetic test found an existing upstream convention: compiled plain
add/subtract can leave dead flags unchanged, while live flag producers/consumers
stay on the careful path. General oracle cases therefore use flag-preserving
operations and still compare flags; the tests do not globally ignore flags.

Review also identified a pre-existing limitation: generic `h_op` does not check
code-write generations as `h_write` does. A raw memory instruction modifying
tracked RAM code may continue in the compiled region. Directly lowered Raw16/32
stores use the existing code-write guard, but other generic stores retain this
issue. It is source-review evidence requiring a dedicated self-modification
regression test; it is not a completed arbitrary-firmware correctness audit.

Private build hashes, source snapshots, complete output/state comparisons and
reproduction scripts remain under ignored `Research/AccelerationNext/`. The v1
and v2 sources/receipts are preserved separately; current `build.py` and `run.py`
default to v3 baseline/combined. No firmware bytes or generated firmware kernels
are included in this document.

## Follow-up experiments on 2026-10-18

The goal is sustained playback with headroom: 1.3× is an initial throughput
target, with 1.5× preferable. Neither number replaces the separate audio deadline
gate. The following are matched **desktop Node/V8** comparisons, not iPhone or
foreground WebKit acceptance. Their different baseline speeds also show why
results from different pairs must not be multiplied.

| Experiment | Baseline → candidate | Decision |
| --- | --- | --- |
| Selective register locals | 0.770× → 0.734×; threshold variants also slower | Reject these variants |
| Selective locals with helper/cap refinements | 0.744× → 0.730× best candidate | Reject these variants |
| Immutable-code tail-call chaining | 0.765× → 0.767× | No material speed claim |
| Larger translated regions | 0.767× → 0.746× / 0.673× | Reject; retired counts also differ |
| Avoid already translated successor duplication, with chaining | 0.740× → 0.856× | Investigate; strict state mismatch |
| Corrected deduplication after unchanged full discovery, without chaining | 0.723× → 0.797× | Passes captured state/phase gates; desktop gain in one pair |
| Exact 240 MHz TIMER4 arithmetic shortcut | 0.774× → 0.756× | No gain in this pair |
| Local mirror of the sticky break flag | 0.760× → 0.766× | No convincing material gain |
| Guarded direct ISR TIMER4 read before any helper | 0.715× → 0.726× | Passes captured state gate; only 1.5% in one pair |
| Specialize CPU1's existing budget-one probe | 0.803× → 0.838× | Passes captured state/phase gates; WK gain only 0.3% |
| Outline the interpreter executor | 0.865× → 0.863× | State gates pass; no gain |
| Outline executor with a fixed dispatcher function boundary | 0.804× → 0.800× | State gates pass; no gain despite much smaller functions |
| Selective register locals only on CPU0 after corrected deduplication | 0.821× → 0.813× | Captured state/phase matches; no gain |
| Corrected deduplication plus immutable-code tail calls | 0.798× → 0.822× | Node +3.0%, but actual WK −4.3%; reject for target runtime |
| CPU0 selective locals with compact declarations | 0.769× → 0.782× | State gates pass; small Node gain, no established WK gain |

Selective-local variants, the clock arithmetic shortcut and the break mirror
matched the full captured PCM, final RAM/LCD/flash, and selected CPU state,
including retired counts, in their matched stress runs. This does not make the
slower variants useful optimizations.

Deduplication reduced emitted code from about 25 MB to 3.84 MB, but nine guest RAM
bytes and retired counts differ. Two words concern firmware-observable stack
watermarks; another word records four additional nested timer observations.
Identical captured PCM does not justify ignoring these differences. Exact event
phase diagnostics subsequently found identical final virtual cycles, pending
interrupts, timer/audio event phase and audio queues, with frame conservation
passing. Deduplication without tail calls has the same differing state as
deduplication with tail calls. Both execute 808 fewer CPU0 instructions and skip
808 more virtual cycles. This isolates the discrepancy to discovery/layout and
execution history rather than the new tail-call ABI or a coarse test endpoint.
In this fresh trio, baseline/dedup/dedup+tail throughput was
0.780×/0.835×/0.834×. The strict acceptance gate remains failed.

The corrected experiment preserves the **entire original breadth-first discovery**
before removing already translated, non-root bodies from the emitted function.
Early pruning had also changed traversal limits and which new blocks belonged
to each region. With the corrected order, baseline and candidate match the full
874,368-frame PCM capture, final guest RAM/LCD/flash, both selected CPU states
including retired counts, and recorded event/audio-queue phase. The A→compiled
B→cold C discovery regression is covered, and both builds pass 14,207 generated
execution cases. Generated text falls from 24,960,585 to 3,198,635 bytes. The
matched Node/V8 pair improves 0.722621× → 0.797471× (+10.36%). This is a useful
correctness-gated candidate, still below real time.

An actual macOS WKWebView pair subsequently improves warm throughput
0.694359× → 0.786566× (+13.28%). Warm render p95/p99 falls from 9.38/10.04 ms
to 7.90/8.30 ms, but the maximum rises from 10.88 to 19.88 ms. Both deliver
874,368 frames over 20 guest seconds with zero warm core shortages; this does
not establish timely audio delivery. AC power, Low Power Mode off, nominal
thermal state and an unlocked session are recorded. The candidate remains
active/visible after startup; the baseline briefly loses activation before the
warm measurement window while remaining visible. Warm condition observations
show activation. This is not pristine whole-case foreground evidence, an iPhone
measurement, or the required real-time/headroom result.

The accepted corrected-deduplication module `6551d0d8…` subsequently completes
a sustained **120-guest-second WKWebView run**, using the same dense project and
input script. Warm 15–120 throughput is **0.796848616×**; render p95/p99/max is
7.82/8.30/15.42 ms. It returns 5,286,272 frames, compiles 4,147 regions and reports
zero warm core shortages. All 75 native condition observations after the first
second (78 total) are
active/visible/unlocked, Low Power Mode off, nominal thermal state; AC power
and fetched module identity are verified. Five-guest-second windows include
0.79135× (25–30), 0.80985× (50–55), 0.79906× (75–80) and 0.80685× (100–105).
There is no observed late tiering jump to real time or sustained collapse.
This establishes sustained sub-real-time throughput for this tested workload;
it is not a paced audio/deadline pass or an arbitrary-firmware guarantee.
It is not a matched comparison with older 120-second baseline runs.

Generated memory-helper call counts identify a more specific target: CPU0 made
23,290,071 TIMER4 reads in the five-second warm profile, about 79.4% of its counted
MMIO accesses. Of those reads, 99.06% saw the peripheral ISR flag set. These are
call frequencies, not host-time percentages or proof of which firmware loop
issued every read. Optimizing the arithmetic alone failed to improve speed;
the next experiment removes the generic helper transition for provably pure
reads inside an uninterrupted translated segment. It must preserve event
boundaries, deferred clock accounting and CPU1's distinct clock behavior, with
the original helper as fallback.

The first direct-read implementation passes 13,743 generated execution cases,
including required observation of fewer actual helper calls, CPU1's fixed-clock
behavior, settled tick debt, prior helpers, both wide-load orders and fresh
metadata pointers after moving peripheral state. Its full captured PCM and final
RAM/LCD/flash/selected CPU state match the baseline. The conservative first
version nevertheless improves only 0.714856× → 0.725657× in Node/V8; coverage
diagnostics then found 23,046,850 successful direct reads versus 256,956 remaining
helper reads in the warm window: **98.897% coverage**. Only 252,190 misses had a
prior helper and 4,766 occurred outside the ISR flag. Relaxing the prior-helper
guard therefore cannot recover substantial extra coverage and is not justified
as the next optimization. Added generated text grows about 35%, while the
overall throughput gain is small. A sampled host-cost profile is needed to
identify the remaining expensive work; call frequency alone was insufficient.

A subsequent host sampling run uses the frozen corrected-deduplication module,
without guest profiling counters, and enables V8's CPU sampler only for the
15.004–20.000 guest-second window. Its 4,171 samples over 6.266 wall seconds
attribute self time approximately as follows:

| Host frame | Sampled self share |
| --- | ---: |
| Generated region code | 36.67% |
| `Cpu::run_fast<Core1Bus>` | 17.41% |
| `Cpu::run_fast<Soc>` | 12.46% |
| `machine::run_cpu1` | 8.06% |
| `exec_fast_paired<Soc>` | 4.28% |
| `run_blocks` | 2.53% |
| `h_read<Soc>` | 1.20% (4.69% inclusive) |

These are sampled attribution results, not additive predicted speedups or a
WebKit/iPhone profile. The profiled run retains byte-identical PCM and recorded
state/phase. It redirects the next experiment toward dispatch and CPU1 probe
bookkeeping, preserving the fixed initial idle-probe snapshot, each original
block boundary, tick accounting and interrupt-check ordering.

The first dispatch experiment specializes the existing `run_fast(..., 1)` call
for CPU1's initial probing phase. It preserves the fixed initial snapshot,
per-block budget reset, subtraction/idle-test order and interrupt checks. The
constant-budget form returns directly where the general loop would immediately
hit its next budget check. Both builds pass 14,400 cases, including 193 direct
old-wrapper/new-wrapper comparisons covering compiled/interpreted/zero-progress,
careful/predicated/glued, interrupt, RAM/code-write and error paths. Complete
heavy-run PCM and recorded state/phase also match.

Its matched Node result is 0.803087× → 0.837824× (+4.33%), but an actual
WKWebView pair is 0.809288× → 0.811838× (+0.315%): essentially flat. WK p95/p99
is 7.74/8.22 ms versus 7.76/8.24 ms. Both complete 20 guest seconds and 874,368
frames with no warm core shortages; all post-startup condition observations
show active/visible/unlocked, Low Power Mode off and nominal thermal state.
The Node gain must not be reported as an iOS-path gain or multiplied into the
earlier WebKit result. The subsequent compiler-layout experiment isolates
outlining `exec_fast`, whose forced inlining enlarges the hot dispatch functions.

Both compiler-layout experiments also pass the 14,400-case gate and complete
captured PCM/state/phase comparisons. Outlining `exec_fast` alone is flat in
Node (0.865345× → 0.862955×) and causes LLVM to inline the smaller dispatcher
into callers. A second, targeted experiment fixes the dispatcher boundary in
both controls before comparing executor inlining. It reduces the standalone
CPU1 probe dispatcher from 9,493 to 2,153 bytes, CPU1 general dispatcher from
18,379 to 3,789 bytes and CPU0 dispatcher from 36,204 to 15,218 bytes, yet remains
flat/slightly slower (0.803796× → 0.800259×). Function size alone was not the
performance bottleneck. Neither variant earns a WebKit speed claim or another
layout-parameter sweep.

A single selective-local retry uses the smaller corrected-deduplication regions,
complete touched/written masks and narrow known-helper barriers on CPU0 only.
An explicit bus capability keeps CPU1 uncached; there is one body per region,
with no runtime budget threshold or duplicated cached/uncached body. Complete
captured PCM/state/phase matches, but throughput is 0.820990× → 0.812670×
(−1.01%). Targeted aliasing/helper-output consumers additionally exercise reload
barriers after unary, division and an unknown helper that overwrites a cached
register. The implementation receives no speed acceptance from this result.

Combining corrected deduplication with the existing immutable-code tail ABI
passes full captured Node state/phase/PCM gates and yields a modest Node gain
(0.798344× → 0.822463×, +3.02%). A direct combined oracle discovers through an
already-owned block, installs the filtered bodies without replacing that owner,
then executes A→B→C→A with 12 retired instructions, 11 ticks and four actual
tail links. In actual WKWebView, however, throughput regresses
0.801095× → 0.766297× (−4.344%); p95 rises 7.86 → 8.28 ms. Both cases have
clean post-startup foreground/unlocked/Low-Power-off/nominal-thermal observations,
verified actual module hashes, flash restoration, 874,368 returned frames and
zero warm core shortages. WK does not capture PCM in this run; an unchanged
initial fingerprint seed is not an audio comparison. Complete PCM equality is
the separate Node proof. The combination is rejected for the target runtime.

The final cache experiment densely maps the completed touched mask into exactly
that many WASM locals, instead of declaring 16 cached GPR locals regardless of
use. Four access sites and the module declaration change; CPU1 remains uncached.
Sparse r0/r15 tests inspect the actual two-local declaration and execute the
generated code, alongside the strengthened helper/barrier suite. Full captured
PCM/state/phase matches in Node, with 0.768578× → 0.781567× (+1.69%). The first
WK pair observes 0.811329× → 0.767158×, but its baseline loses activation during
warmup and remains visible/inactive in the measurement window. It is therefore
foreground-confounded, not pristine regression proof or evidence of a WK gain.
WK PCM is not captured in this run.

A single clean repeat resolves that environmental ambiguity: both cases retain
active/visible/unlocked, Low Power Mode off and nominal thermal state in all
12/12 post-startup observations. Warm throughput is 0.800695× → 0.767780×
(−4.11%). Exact fetched modules match their frozen hashes. Thus compact locals
also earn no speed acceptance in the target engine; no further mask or local
layout sweep follows from these results.

## Multi-block CPU1 trace prototype

A subsequent authorized architecture experiment implements a separate CPU1 trace
cache and generated module mode, retaining guest GPR locals across original
probe checkpoints. It uses only already decoded and already compiled original
blocks, without changing normal discovery, ownership or hot counters. Code-write
generation changes invalidate traces; missing guards use the original engine.
The fixed initial probe, per-block first-tick omission/budget reset, saturating
left/probing accounting and idle-before-next-IRQ ordering remain explicit.

A deterministic 1/64 sample of the primary workload's guest 15–20 second window
observes 18,323 CPU1 scheduler invocations and 1,431,137 block events. Plain,
helper/MMIO/careful/partial-free work with no routed CPU1 interrupt accounts for
95.44% of sampled retired instructions. Requiring no pending peripheral interrupt
at all would reduce coverage to 0.159%: CPU0 interrupts are usually pending, while
CPU1 routing is clear. These are sampled eligibility counts, not predicted gains.
The observational build matches the frozen baseline's complete captured PCM,
RAM/LCD/flash, CPU and exact phase bytes.

Prototype v1 fails the full workload state gate despite identical captured PCM.
Its trace compilations consume the normal compilation allowance, altering normal
interpreter-versus-compiled decisions. Separating the trace compilation allowance
produces v2, which passes the complete 20-second captured PCM/state/phase gate
against frozen corrected-deduplication module `6551d0d8…`. V2 SHA-256 is
`dad6a6c9bee650f869e35548ae51cf59893c12508413bcf6988419d4ff316e14`.
It executes 502,175,833 instructions across 97,323,453 checkpoints in 34,114,873
trace calls, with no module failures. Mean reuse is only 2.85 checkpoints/call.

This first correct prototype is **not a performance success**: its diagnostic
Node warm throughput is 0.621×, with no accepted matched runtime speedup.
Normal-context expansion and memory-heavy checkpoint bookkeeping are being
separated from the normal path before a fair trace-off/control/candidate test.
Independent actual scheduler/checkpoint tests subsequently pass **280 targeted
cases**, comparing 21,172 original checkpoints and 10,806 trace checkpoints.
Of those, 3,042 trace checkpoints execute while CPU0 interrupts are pending and
CPU1 routing is clear. The tests compare virtual/canonical architecture and
counts, k/left/probing/idle/budget, synthetic RAM/code flags/LCD/flash/audio,
exact phase, errors, final state and the original compile-allowance remainder.
A broader Cartesian attempt was stopped incomplete and is not counted as a
pass. Full PCM equality alone does not establish every internal checkpoint.

Read-only coverage analysis identifies a substantive restriction: blanket
rejection of glued instruction pairs excludes pairs the original block builder
already proved independent (`careful=false`), fragmenting hot loops. A staged
candidate will allow only contained, proven-safe pairs using the shared emitter's
existing first-half hold/exit handling, and add direct positive/partial-pair tests.
It also restores the ordinary helper/context path and retains private checkpoint
bookkeeping in WASM locals. The resulting v4 candidate preserves full 20-second
heavy-workload PCM/RAM/LCD/flash/CPU/phase equality against the frozen control.
Independent checks pass **304 cases / 23,102 original checkpoints**, including
12,028 trace checkpoints, safe multi-block glued pairs and first-half helper /
code-store recovery. All 27 source files match the frozen production candidate
after declared observer hooks are removed. The narrow bus-only helper contract
is explicit: Core1Bus cannot inspect CPU registers and has no independent clock.

V4 executes about 49.95% of CPU1 instructions inside traces, averaging 11.48
original blocks and 86.47 instructions per trace call. Its earlier diagnostic
Node warm throughput was 0.702×; that isolated run is not a matched speedup claim.
Emitted trace code grows to approximately 38.89 MB across 886 regions.

A subsequent same-session three-way Node/V8 control uses the same 20-second
primary workload and guest 15–20 second warm interval. Runs are serial, on AC
power, with Low Power Mode off, nominal thermal state and loginwindow not
frontmost at preflight:

| Implementation | Warm useful audio / wall | Render p95 / p99 |
| --- | ---: | ---: |
| Frozen corrected-dedup baseline `6551d0d8…` | 0.772691× | 8.09 / 8.65 ms |
| Candidate source with traces disabled `b7889089…` | 0.746410× | 8.29 / 9.00 ms |
| V4 traces enabled `2cc8281c…` | 0.733895× | 8.81 / 9.53 ms |

V4 is 5.02% slower than the frozen baseline and 1.68% slower than its own
trace-disabled control in this bounded comparison; the trace-disabled source is
itself 3.40% slower than the frozen module. Full captured PCM, RAM/LCD/flash, CPU
and exact phase bytes match across all three. Each returns 874,368 audio frames,
with 640 cold missing frames and zero warm missing frames. V4 executes
1,087,281,178 instructions across 144,300,193 original checkpoints in 12,574,242
trace calls. These Node results reject a speedup claim for v4; they do not measure
WebKit or establish iPhone headroom. The private receipt is
`Research/TraceEngine/node-controls.json`.

The independent 304-case oracle applies to this exact v4 production source:
27 candidate files match after only declared observer hooks are removed, with
716 generated modules and zero compilation failures. Its checkpoint-level
synthetic cases and the full heavy-workload final-state comparison are separate
evidence; the heavy workload did not produce an independently compared stream
at every internal checkpoint. The Core1Bus helper exemption, preserved original
idle heuristic and untested arbitrary-firmware/hardware behavior remain limits.

The next candidate shares one generated checkpoint at the dispatch-loop header
instead of duplicating it on every edge. Its full 20-second heavy-workload gate
passes captured PCM, RAM/LCD/flash, CPU including retired counts, exact phase,
audio frames and shortages against the frozen baseline. Runtime trace counts
remain exactly those of v4, while generated trace bytes fall from 38,887,481 to
7,919,036 across the same 886 regions (79.64% smaller), with zero compilation
failures. Candidate WASM SHA-256 is
`d4cf83ba0c03e33f0ac7265f6e73587569a32b615fe6079d5b175b1b5c7f96f0`.

This common-header candidate reaches 0.853088× warm throughput in Node, with
render p95/p99 of 7.34/7.92 ms: 16.24% above v4 and 10.40% above the preceding
same-session frozen control. This is a bounded Node improvement, below both real
time and the 1.3× headroom target. The private receipt is
`Research/TraceEngine/header-comparison.json`. A separate independent gate then
passes 314 cases / 23,908 checkpoints, including four 33-operation bound cases;
its provenance matches all 27 production source files after observer removal.

The first actual WKWebView Worker trio measures frozen / trace-disabled / header
at 0.765862× / 0.754833× / 0.761819×, so the Node gain does not transfer: header
is 0.53% below frozen. Its host remains active, visible, unlocked, on AC, with Low
Power Mode off and nominal thermal state. Frames, shortages and LCD fingerprints
match. However, those cases disable PCM capture, exposing an existing harness
expression that leaves the audio hash at its initial seed with zero hashed
frames. Their audio hash is not PCM evidence; full Node byte parity remains a
separate gate. The original receipts are retained in
`Research/TraceEngine/wk-summary.json`.

A separate cumulative-accounting candidate retains every original checkpoint,
exit test and 64-block cap. It holds the initial left/probing and counter bases
immutable, accumulates retirement debt, and materializes the same saturated
left/probing and wrapping counters at every observer and exit. Debt is bounded
by 64 × 33 = 2,112; the implementation adds one WASM local. Its production module
`242368e2d63856fc50dbacbddbf2ff47a95a6772baeefc1ad87d07978d8f2899`
passes the 16,207-case legacy emitter suite and full 20-second captured
PCM/RAM/LCD/flash/CPU/phase/frame/shortage equality against both frozen and header.
Trace calls, retired instructions and checkpoints remain exactly unchanged;
trace bytes are 7,914,606. Its independent oracle passes **326 cases / 24,920
checkpoints**, including nonzero/wrapping counter bases, high unsigned inputs and
repeated read-only observer materialization. Its Node warm result is 0.844989×;
this isolated result supplies no gain over the earlier header run.

A fresh actual WebKit trio enables PCM capture and the same full-frame hashing
work for every variant:

| Implementation | Warm useful audio / wall | Render p95 / p99 |
| --- | ---: | ---: |
| Frozen corrected-dedup baseline | 0.773768× | 8.10 / 8.56 ms |
| Common-header trace | 0.783084× | 8.22 / 8.78 ms |
| Cumulative accounting | 0.779724× | 8.28 / 9.22 ms |

All three hash the actual 874,368 captured frames to `07d28989`, with matching
frame/shortage/LCD results and zero warm missing frames. This is a full-frame
fingerprint comparison; complete PCM byte equality is the separate Node gate.
Per-frame conversion, hashing and PCM-array writes are inside the warm timing
interval for all three; final transfers/state copies occur after its end time.
Per-case fetched-module SHA matches its pin, with AC power and active, visible,
unlocked, Low Power Mode off, nominal-thermal observations throughout the run.
The owned private server is stopped after completion.

Accounting is 0.43% below header and 0.77% above frozen in this bounded trio,
which is flat for acceptance purposes. Neither candidate reaches real time or
the 1.3× headroom target, and neither earns a target-WebKit improvement claim.
Receipts and timing-method details are under ignored
`Research/TraceAccounting/`, with independent gate provenance in
`Research/TraceOracle/accounting-provenance.json`.
A subsequent sample of the owned WebContent process sees active OMG background
compilation, while 2,590 of 2,686 Worker snapshots remain unresolved native JIT
addresses. It cannot divide execution between generated traces, Rust dispatch
and JavaScript, or establish a register-spill cost. Current upstream WebKit has a
[worker ScriptProfiler sampling protocol](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/inspector/protocol/ScriptProfiler.json)
and a [WASM name-section profiler regression test](https://github.com/WebKit/WebKit/blob/main/JSTests/stress/sampling-profiler-wasm-name-section.js).
Those are source capabilities; named sampling of this installed WKWorker has
not been demonstrated. A tiny separate local JSC capability probe resolves a
named interpreted WASM frame, but its Python-hosted VM has JIT disabled and
cannot substitute for the actual WebKit Worker. Findings are private under
`Research/TraceAccounting/jsc-research/`.

A separate entry-path candidate derives from the common-header source, without
combining cumulative accounting. It captures the fixed initial probe once per
`run_cpu1`, moves stable memory-map lookup to cold compilation, and reuses the
caller's routed-CPU1-IRQ proof under the serial Core1Bus contract. Every bus read,
write, lock and IRQ-window operation invalidates that proof. Normal cache-reset
and global code-generation epochs still guard cached trace membership. Unknown
buses fail closed. Its production module
`a96d2b98018d7b757d0deb656c08c25a28611b417cdeea3f89b8349bca235599`
passes the 16,207-case emitter suite and full 20-second PCM/RAM/LCD/flash/CPU/
exact-phase/frame/shortage gate. Runtime calls, retired instructions, checkpoints
and generated trace bytes remain exactly those of header.

The entry oracle passes **326 retained cases / 24,920 exact checkpoints plus
15 direct proofs (341 cases total)**. Added checks exercise all eight proof
invalidators, real IRQ-routing MMIO, cold normal HOT/compile-allowance preservation,
trace heating, cold-only memory-map queries, normal-only reset, code epoch and
consumed-budget rejection. All 27 source files match after declared hooks are
removed. A fresh native WK pair, with capture and full-frame hashing enabled for
both, measures header **0.753326×** and entry **0.778267×** (+3.31%). It is a
bounded matched improvement over header, still below real time and the 1.3×
reserve gate. It is not a matched comparison against frozen or accounting, and
must not be combined numerically with their earlier controls. Both cases hash
874,368 frames to `07d28989`, with identical frames/shortages/LCD and successful
flash roundtrip, pinned module hashes and clean native conditions. Receipts:
`Research/TraceEngine/wk-entry-pair-summary.json` and
`Research/TraceOracle/entry-provenance.json`.

One final structural candidate derives separately from frozen header. Its
read-only collector selects a generic static backward-taken/forward-not-taken
path over already decoded, normally compiled blocks, bounded before insertion
at 16 blocks and 128 operations. No firmware PC or identity whitelist participates.
Only the root binds an entry; other entries fall back. Each original block has
one common end checkpoint, followed by an expected-successor guard and direct
fallthrough or a direct branch to an earlier loop label. Cold/computed/partial
exits retain the exact completed original checkpoint. All 16 GPR locals remain
initialized and flushed; no mask or checkpoint coarsening is introduced.
Trace chaining is disabled; the earlier header measurements also used chain=0,
and its reused locals were not validated with trace chaining enabled.

The linear production module
`b12d94c66b6d6e79649d7227aa227b162519125673a1bf490e28882b55bd0bcc`
passes the 16,207-case emitter suite and full 20-second captured PCM/RAM/LCD/
flash/CPU/exact-phase/frame/shortage equality, with zero compilation failures.
Its independent oracle passes **339 cases / 25,648 exact original checkpoints**
and 999 generated modules, including cold edges at early/middle/late positions,
computed exits, path limits, glued helper/code-store exits, counter wrapping and
root-only fallback. All 27 files match the production freeze after hooks are
removed. A further focused case now passes 257 exact checkpoints, including
256 traced checkpoints in four calls and a fifth checkpoint in the same first
trace call. This proves execution of the taken depth-three conditional backedge,
which the fixed-snapshot idle test could otherwise stop at its first loopback.
The original 339-case receipt remains unchanged; combined evidence is **340 cases
/ 25,905 exact checkpoints**, with the focused receipt retained separately in
`Research/TraceOracle/linear-backedge-result.json`.

A fresh, serial native WK trio uses identical inputs and full-frame hashing:

| Implementation | Warm useful audio / wall |
| --- | ---: |
| Frozen corrected-dedup baseline | 0.771938× |
| Common-header trace | 0.782804× |
| Static linear path | 0.752546× |

Linear is 2.51% below frozen and 3.87% below header; header is 1.41% above frozen
in this short trio. All cases actually hash the same 874,368 frames to
`07d28989`, with matching frames/shortages/LCD, successful flash roundtrip,
verified fetched hashes and active/visible/unlocked/AC/LPM-off/nominal-thermal
steady observations. The owned server stops after completion. Full CPU/phase
byte proof remains the separate full-workload Node gate and checkpoint oracle;
the WK run does not independently dump those fields. Receipts:
`Research/TraceEngine/linear-wk-result.json`, `linear-comparison.json` and
`Research/TraceOracle/linear-provenance.json`.

The linear result does not isolate dispatch cost: static root-only path selection
raises trace calls from 12,574,242 to 37,067,799, while checkpoints per call fall
from 11.48 to 3.65. Traced retirement falls 3.96%, and generated bytes grow from
7,919,036 to 8,348,857 across 1,154 regions. Its isolated Node result is 0.775981×.
Extra exits and entry synchronization confound the direct-branch change; this
trial cannot establish that dispatch is cheap or that another structured CFG
cannot help. The candidate earns no real-time/headroom acceptance. No additional
candidate is implemented in this bounded trial; stable iOS archives and the
installed app remain unchanged.

The earlier unlocked sustained control runs a fresh, serial **120-guest-second actual WebKit
pair**, using the exact extended primary script, 240 MHz clock, package and flash.
Both cases capture and hash every audio frame with identical harness work.
The older 0.796849× frozen result remains historical; the fresh control supplies
the denominator here:

| Implementation | Cold 0–15 useful audio / wall | Warm 15–120 useful audio / wall | Warm render p95 / p99 |
| --- | ---: | ---: | ---: |
| Frozen `6551d0d8…` | 0.868060× | 0.806275× | 7.72 / 8.24 ms |
| Common-header `d4cf83ba…` | 0.854410× | 0.838628× | 7.68 / 8.36 ms |

Header gains **4.01%** over the fresh warm control in this single matched pair.
For the actual guest 100.002–120.004 interval, useful audio / wall is
0.809168× → **0.854550×** (**+5.61%**). The four late windows are:

| Actual guest seconds | Frozen → header throughput | Frozen p95 / p99 | Header p95 / p99 |
| --- | ---: | ---: | ---: |
| 100.002–105.004 | 0.784369× → 0.838739× | 8.00 / 9.02 ms | 7.64 / 8.34 ms |
| 105.004–110.000 | 0.811735× → 0.850838× | 7.64 / 8.14 ms | 7.60 / 8.32 ms |
| 110.000–115.002 | 0.819366× → 0.866068× | 7.46 / 7.90 ms | 7.26 / 7.78 ms |
| 115.002–120.004 | 0.822336× → 0.863102× | 7.46 / 7.92 ms | 7.30 / 7.92 ms |

Late pooled quantiles were not captured; the window percentiles are not averaged.
All 24 five-second windows remain in the raw receipt. Both cases actually hash
**5,286,272 frames** to `873b478f`, with LCD fingerprint `63c02727`, identical
5,286,912 requested frames, 640 cold missing frames and zero warm missing frames.
These are full-frame WK fingerprints; full CPU/RAM/phase byte parity remains the
separate 20-second Node gate. Fetched module hashes match their pins. Native
post-startup observations are clean in 74/74 frozen and 72/72 header records,
with 16/16 AC-power readings per case; all are active, visible, unlocked,
Low Power Mode off and nominal thermal state. Owned hosts and the private server
are stopped after completion.

The late windows still install 202 / 220 generated modules for frozen / header,
with 118.76 / 175.94 ms of synchronous compilation. These counters do not measure
background OMG tiering or prove compiler quiescence. The modest later gain does
not identify its cause, and there is no late jump to real time. Warm p99 is
slightly worse for header, so this is not an audio-deadline acceptance result.
Source, raw host/condition records, exact fetched hashes, all windows and cleanup
receipts are retained under `Research/TraceAccounting/Sustained/`; the compact
result is `result-receipt.json`. No further candidate or runtime gate is pending
in this bounded trial.

## Ordinary Mac Chrome comparison

A later exploratory run uses an ordinary **Chrome 155 tab on the same Mac**,
with the same frozen `6551d0d8…` and common-header `d4cf83ba…` WASM, extended
120-guest-second inputs, package, flash, clock and `capturePCM:true`. The copied
Worker and worklet are byte-identical to the sustained WK harness. Fetching,
launching and saving stay outside the worker measurements; PCM conversion,
capture and hashing retain their original measured cost. This measures unpaced
Worker throughput, not browser audio-device playback.

**The browser control path is a major measurement confound.** The first pilot
in a directly controlled tab reaches only 8.25 guest seconds in 70.06 wall
seconds. A separate `target="_blank" rel="noopener"` child, never claimed or
read through browser control during execution, completes 20 guest seconds in
22.31 wall seconds while the Mac remains locked. For the exact shared cold
0–5 guest-second interval, both perform the same frame, region, generated-byte
and budgeted-instruction work; throughput is 0.165240× versus 1.362408×
(**8.245×** difference). This does not prove a V8 debug-tier cause. The truncated
controlled pilot is excluded from warm and sustained comparisons.

The fresh, serial detached Chrome pair completes normally:

| Implementation | Cold 0–15 audio / wall | Warm 15–120 audio / wall | Late 100.002–120.004 | Warm render p95 / p99 |
| --- | ---: | ---: | ---: | ---: |
| Frozen `6551d0d8…` | 0.923679× | 0.825108× | 0.834815× | 7.450 / 7.945 ms |
| Common-header `d4cf83ba…` | 0.910598× | 0.852431× | 0.849134× | 7.555 / 8.275 ms |

Header improves warm throughput **3.31%** and late throughput **1.72%** in this
pair. It remains below real time and needs about **52.5% more throughput** to
reach 1.3×. Both pooled warm tail percentiles worsen; this is no audio-deadline
acceptance. Late pooled quantiles are unavailable; the four individual late
windows and all 24 windows per case remain in the receipts.

Both cases finish at 120.004 guest seconds and hash all **5,286,272 real audio
frames** to `873b478f`, with LCD `63c02727`, 5,286,912 requested frames, 640 cold
missing frames and zero warm missing frames. Actual fetched WASM pins, package
and script hashes match. This is fingerprint equality, separate from the prior
full-byte Node parity gates. Native condition samples are locked in **17/17
frozen and 16/16 header** records, with AC power, Low Power Mode off and thermal
state 0 throughout those samples. DOM visibility/focus remain true despite the
native lock; they do not establish an unlocked session.

A fresh native WK control in the same locked session reaches only **47.958 guest
seconds in 250.043 wall seconds**, then stops at the original wall bound. The runner records failed completion
validation because the requested 120 guest seconds were not reached; this is an expected
bounded diagnostic, not an application crash. Its
127 native observations are locked, inactive and occluded; 26 AC checks pass,
with Low Power Mode off and thermal state 0. The header case is not run. This
incomplete diagnostic supplies **no matched Chrome/WK throughput ratio** or
120-second warm/headroom result. The earlier unlocked WK pair above remains a
separate context, not a fresh browser control. Neither the pilot discrepancy nor
this WK slowdown identifies compiler tiering, background load or throttling as
the cause.

Private raw results, actual hashes, condition records, comparison JSON and a
local report are under `Research/BrowserCompare/`. Owned WK hosts and port8769
are stopped; root owns cleanup of the Chrome tabs and loopback report server.
No firmware/source is published, and no product or stable archive is changed.

Private sources and receipts remain under ignored `Research/TraceEngine`,
`Research/TraceProfile`, `Research/TraceAccounting`, `Research/TraceOracle` and
`Research/BrowserCompare`.

## Is the stress project feasible on a physical FM-1?

A source-and-fixture audit on 2026-10-18 changes the interpretation of the
extreme benchmark. It is a legal boundary/overload fixture, **not a certified
maximum workload that physical FM-1 hardware can sustain**. The earlier host
throughput measurements remain valid for their recorded emulator workload;
they do not by themselves establish that the hardware can play that project
without overload handling.

The pinned mixed FM6/PHYS/GRAIN flash really contains all 64 filled steps:
four, two and two synth notes plus all 16 drum lanes on every step, all with
four ratchet hits. The nominal demand at 240 BPM and 1/32 division is:

```
steps/s = 240 / 60 * 8 = 32
sequencer trigger attempts/s = 32 * 4 * (4 + 2 + 2 + 16) = 3,072
```

The input script adds eight kick/lane-zero presses per second after guest
second 10. Late sequencer servicing can skip intermediate ratchets, so these
are requested rates, not measured runtime call counts or 3,080 simultaneous voices. SLOOP
has eight shared non-fading synth voices, six drum slots and twelve grain
slots per GRAIN part (one in this fixture), with additional engine-specific
limits and voice stealing. Brief fading steal tails can still render. Its audio ISR requests
voice shedding after two consecutive halves above 85% inclusive processing
time. Legal parameter ranges therefore do not guarantee that every configured
voice/effect remains audible without shedding. Maximum controls also do not
prove the globally most expensive possible engine state.

For each 256-frame audio half the physical deadline is approximately
`256 / 44,100 seconds = 5.804989 ms`. The modeled 24 MHz / 544 divider gives
44,117.647 Hz and a 5.802667 ms deadline. Conditional per-core budgets are
1,392,640 cycles at 240 MHz or 2,088,960 at 360 MHz using that divider. A useful
deadline test is the serial work plus `max(core0 work, core1 work)`, joining
and nested interrupt time fitting within the half; adding both cores' cycle
budgets does not prove the critical path fits.

There is an unresolved timing-calibration issue: the emulator uses 240 MHz
and approximately one guest instruction per virtual cycle, while the pinned
SLOOP source describes a 360 MHz bootloader clock. The application does not
itself establish that clock, and a source comment is not a measured PLL
configuration. Cache, memory, instruction and parallel-core timing are not
hardware-calibrated. Do not rescale the existing throughput by 360/240 or
divide instruction totals by MHz as a hardware capacity proof.

An existing emulated RAM snapshot contains firmware timing counters, but
those use the emulator's timer. Moreover, audio `max_us`/`cpu_q8` exclude nested
TIMER5 time, while shedding uses inclusive time. These counters cannot certify
physical deadlines, absence of shedding or uninterrupted real-time audio.

The acceptance matrix should separate a representative project, a heavily
loaded project verified to fit hardware, and this boundary/overload diagnostic.
Keep the extreme fixture for regression and overload behavior; do not make it
the sole real-time product acceptance gate. To certify hardware feasibility,
run the same saved project on a physical FM-1, verify its actual clock, and
record warmed inclusive half-duration tails/max, late-counter deltas, CPU1
busy/wait and fallback, and shed events alongside the audio. Require spare
time for the hardware-valid tier. Lower note density alone need not improve
emulator throughput proportionally because guest polling/main-loop work also
consumes host time.

Private, hash-pinned source and fixture evidence is retained under
`Research/StressFeasibility/`; no product engine, firmware or installed app was
changed for this audit. Upstream descriptions:
[SLOOP capabilities](https://github.com/isod89/sloop-fm1/blob/main/README.md)
and [v2.7 dual-core release](https://github.com/isod89/sloop-fm1/releases/tag/v2.7).

### Follow-up: conditional hardware-clock change

The user requested a matching hardware clock only if it could be established
quickly and changed safely. A bounded source/binary audit extracted the actual
pinned SLOOP package's 14,536-byte SPL; its SHA matches the SDK pin. The embedded
45-byte configuration has no SYS_CLK override. A decoded frequency-selection
routine offers several frequencies, but neither its option table nor a 240 MHz
literal proves the selected boot default or effective PLL/divider state. The
240 MHz emulator-author description and 360 MHz firmware-author descriptions
remain conflicting evidence, not a live clock measurement.

No clock default was changed. The iOS binary path explicitly uses 240 MHz and
a fixed 4M-slot render cap. A 512-frame request represents about 11.61 ms of
audio, while 4M nominal slots represent only 11.11 ms at 360 MHz (16.67 ms at
240 MHz). Skipping and block overshoot affect exact behavior, but blindly
changing only the clock introduces a clear shortage risk. Source-native SLOOP
is frame-driven and has no emulated CPU-clock setting; it is unaffected.

The private WASM harness already accepts an explicit boot-time MHz parameter
and scales its work cap. A 360 MHz research trial needs no rebuild, but it would
be model sensitivity, not a verified hardware correction. Higher virtual CPU
frequency permits more guest work per audio second; it is not a host speedup.
Physical-clock proof, coherent render budgets and targeted peripheral/CPU1
checks are required before changing product policy. No new runtime tests were
performed for this audit. Private evidence: `Research/ClockAudit/` and
`Research/StressFeasibility/clock-audit/`.

## Fresh three-tier workload comparison

The subsequent 2026-10-18 trial uses the same accepted common-header
`d4cf83ba…` WASM, SLOOP 2.7.1, 240 MHz virtual clock, byte-identical historical
Chrome Worker/worklet, 128-frame quantum, full PCM capture/hash work and
15-second warmup. Normal and heavy are newly generated, independently decoded
saved projects; their five storage objects pass payload/header CRC and project
FNV checks. Only project payload/checksum bytes differ from the preserved
boundary flash. Normal/heavy scripts press/release PLAY only. The boundary
flash and extended input script remain byte-identical to the earlier tests.

One detached ordinary Chrome child, unclaimed/unread through browser control
during runtime, executes fresh Worker/WASM instances serially in fixed
normal/heavy/boundary order. Each completes 120.004 guest seconds:

| Tier | Nominal requests/s | Warm 15–120 audio/wall | Late 100–120 audio/wall | Warm render p95 / p99 |
| --- | ---: | ---: | ---: | ---: |
| Normal: 120 BPM, 1/16, three single-note synth lines, sparse drums, mild FX | 31 | 1.213553× | 1.207394× | 5.275 / 5.745 ms |
| Heavy: 160 BPM, 1/16, 4/2/2-note chords on alternate steps, x2, moderate FX | 104 | 0.964458× | 0.966926× | 6.575 / 7.155 ms |
| Preserved boundary project and 8 Hz pad script | 3,080 | 0.854904× | 0.865219× | 7.525 / 8.240 ms |

All three have zero JIT compilation failures and zero warm missing core frames;
each hashes all 5,286,272 delivered frames. Normal/heavy/boundary FNV values
are `2222aefc`/`f77e1d42`/`873b478f`; different content should not have equal
hashes. The boundary hash matches the historical fixture. Native observations
are locked in 12/12, 15/15 and 16/16 samples, respectively; all recorded power
checks are AC, Low Power Mode off and thermal state 0. This is one fixed-order
sample per tier, not a repeated randomized experiment. Cross-navigation engine
cache/tiering carryover is unmeasured. Do not pool with historical unlocked WK
measurements or attribute the whole difference to note count alone: patterns,
effects and active voice behavior differ as documented.

Separate 35-second diagnostic cases snapshot emulated DBG1 at actual guest
14.993 and 35.000 seconds; their timings are excluded from the throughput
table. Every tier advances 3,448 completed halves with **late delta zero**.
Absolute late is 0→0 for normal/heavy and 1→1 for boundary. End cumulative
`max_us` is 2,000 / 3,337 / 4,570 and smoothed `cpu_q8` load is
22.266% / 42.188% / 70.703%, respectively. These TIMER4-derived model metrics
exclude nested TIMER5 work; the maximum includes boot and omits any current
unfinished ISR. Inclusive time, adaptive shedding and CPU1 busy/wait/fallback
remain unknown because no matching ELF/map or independently validated global
addresses were found. Zero late delta does not certify absence of shedding,
complete sample delivery or physical hardware capacity.

The normal project exceeds average real time in this Mac Chrome path, but still
needs about 7.1% more throughput for the 1.3× target. Heavy needs about 34.8%
and boundary about 52.1%. This demonstrates why the boundary fixture must not
be the only performance gate; it does not establish universal FWSC real time.
Unpaced Worker throughput and host render quantiles are not audio-device
callback deadlines, listening acceptance or iPhone performance. Physical FM-1
feasibility remains unmeasured. No engine optimization was made in this trial.

Private generated fixtures, independent reviews, six saved result receipts,
analyzer and reports live under `Research/StressFeasibility/` and
`Research/TraceOracle/`. Owned port8770 server, bounded caffeinate assertion
and both created Chrome tabs were closed after the six results saved. Stable
iOS engine, installed app and frozen archives remain unchanged.

## Current outcome

The accepted improvement is corrected full-discovery region deduplication on
top of the paired-operation/memory emitter. The generic binary-translation path
does not require a firmware hash whitelist or firmware source, but universal
compatibility and real-time speed for arbitrary uploaded FWSC are **not proven**.
The earlier unlocked common-header trace measures 0.838628× warm and 0.854550×
late on this Mac's WebKit path, against fresh frozen controls of 0.806275× and
0.809168×. This is a modest measured improvement in one matched pair, still below
real time and the 1.3× headroom target. Reaching 1.3× from header's warm result
needs about **55% more throughput**, or **35% less host time**; the late result
still needs about 52% more throughput. Neither this comparison nor the earlier
0.796849× historical baseline establishes iPhone or audio-deadline acceptance.
The later locked-session ordinary Chrome pair measures 0.825108× frozen and
0.852431× header warm throughput, still below real time. Its browser-control
confound and incomplete fresh locked WK diagnostic prevent a matched engine
comparison; the historical unlocked WK numbers are not pooled with it.
The subsequent three-tier Chrome trial above reaches 1.213553× for a normal
project and 0.964458× for heavy, versus 0.854904× for the preserved boundary
case. A claim that all SLOOP projects fail average real time would therefore
be incorrect; broad compatibility, audio deadlines and the 1.3× target remain
unproven.

The substantial design under investigation is trace compilation with guest register state
retained across multiple blocks and exact CPU1 probe checkpoints. It must
preserve the fixed initial probe, original per-block return/idle/IRQ ordering,
clock debt and RAM-code validation. This targets generated-code work and
repeated dispatch together. It now has correctness-checked research prototypes and a modest sustained local
WebKit gain for the common-header variant. The accounting and static linear
variants supply no additional accepted speedup. Stable iOS archives and the
installed app remain unchanged; these experiments and validation ran only on
the Mac.

## Initial hypotheses and larger remaining directions

The following records the initial rationale. The outcome table above supersedes
the proposed small selective-local, tail-call and compiler-layout experiments;
negative variants are not pending recommendations to repeat.

1. **Selective register locals combined with useful hot traces.** Cache only the
   registers actually referenced by a region, flush only its written set, and
   reload the required set around generic helpers. Determine both unions before
   emitting any exit, including backedges. The eager-cache failure is consistent
   with excessive entry/helper sync work, especially CPU1's short runs. First PoC:
   two-pass emitter masks, conservative helper synchronization, a structural
   minimum-work threshold, and exact-state plus baseline/candidate A/B gates.
   This changes generic code generation, not a firmware whitelist. It cannot
   inherit the eager cache's correctness or performance result automatically.

2. **Profile-guided region layout and guarded tail-call chaining.** Current
   breadth-first discovery spends its region budget on both hot and cold edges
   (`fm1-core/src/lib.rs:611`); CPU1's polling probe also requests single-block
   runs (`fm1-soc/src/machine.rs:144`). Record executed edges and exit reasons,
   then build one bounded hot trace instead of simply increasing function size.
   Cross-region WASM tail calls could avoid repeated Rust dispatcher entries.
   [WebKit documents tail-call support and its use for interpreter/emulator state
   machines](https://webkit.org/blog/16301/webkit-features-in-safari-18-2/).
   This requires a feature probe and an ABI for cumulative instruction/tick
   consumption; it is not an opcode substitution. Keep MMIO, interrupts,
   code-generation guards and CPU1 scheduling caps exact. First PoC: two connected
   regions with helper/budget/code-change exits, then one matched workload A/B.
   Selective register caching can subsequently extend across a proven trace.

3. **Prove idle work before skipping it.** SLOOP's source main loop repeatedly
   calls input/editor services until a 15 ms frame deadline. That suggests possible
   avoidable work, but these calls consume events, update memory and read clocks;
   the loop is not an unconditional sleep. Existing TIMER4 skipping already
   requires close polls, and explicit `idle` already advances to the next event.
   A new generic optimizer needs a trace certificate: stable live state/read set,
   no unaccounted RAM/MMIO side effect, tracked cross-core writes, and the earliest
   timer/input/DMA/deadline that can change control flow. First PoC only counts
   certifiable loops and potential skipped cycles. PC/register equality alone is
   insufficient; the existing CPU1 heuristic must not simply be generalized.

Parallel guest-core execution is a larger alternative. Both emulated cores share
one mutable SoC; CPU1 currently has no independent clock and receives CPU0's
elapsed-cycle budget in serial 1,024-instruction slices
(`fm1-soc/src/machine.rs:179`). Parallel Workers would need shared-memory rules,
virtual-time barriers and deterministic RAM/mailbox/MMIO ordering, possibly
conflict detection/rollback. Instruction shares do not imply a 2× host gain.
Measure independent compute windows before considering this rewrite; selective
locals and hot traces have a smaller implementation and verification surface.

The clock model itself uses one guest instruction per cycle at 240 MHz, rather
than hardware-calibrated cache/memory/operation latency. Arbitrary clock reduction
is not an acceptable optimization; hardware timing calibration is separate work.

## Why the existing strategies do not multiply

Static768 kernels and dynamic WASM translation both specialize decoded operands
and remove dispatch. Their gains overlap, and a native static kernel is not a
function that WASM can directly call without another boundary. The WASM backend
already implements caching, regions, ordinary memory fast paths and local jump
resolution. Source-native SLOOP additionally bypasses guest CPU execution and
changes the hardware/main-loop model; its speed cannot be transferred to an
arbitrary FWSC without an equivalent generic semantic proof.

The remaining questions are translator overhead versus genuinely executed guest
work, and whether a measured improvement survives the actual WebKit/audio path.
These experiments establish neither iPhone deadlines, long-session thermals,
listening quality, App Store acceptance nor universal real-time playback.

## 2026-10-18: actual app path and fresh heavy comparison

The experimental WASM backend is now available beside Native SLOOP in local
build 0.3.7 (12). Functional installation and PCM delivery passed on iPhone 12,
but audio performance did not: a short isolated smoke missed 8.57% of output
frames; a later owner-session diagnostic reported mean render budget 151.4%,
p95 233.8% and 34.96% missing output frames at thermal state 2. A warmed,
unpaced Mac throughput result is not evidence of iPhone audio acceptance.

Actual Mac WebKit audio-paced tests with the sequencer stopped measured about
6.6 ms per 512-frame block at idle and 8.0 ms with repeated notes. Switching
the producer timer to MessageChannel did not materially improve this path,
including an explicitly synthetic starvation test; no timer patch was applied.
Periodic 1 MiB base64 encoding was observed on the producer. A subsequent local
fix moves encoding to the page host using an independently copied transferable
buffer. Node and actual WK saved-flash equality/recovery tests passed; the
exploratory before/after timing pair was confounded, so no audio-speed gain is
claimed. This correction has not yet been installed on the phone.

A fresh serial Chrome 155 heavy-project comparison used 120 guest seconds per
case, a 15-second warmup, fixed 240 MHz, full PCM hashing, active visible tabs,
AC power, Low Power Mode off and thermal state 0 throughout:

| Generic translator | Warm throughput | Final 20 guest seconds |
|---|---:|---:|
| Accepted common-header baseline | 0.9583× | 0.9643× |
| Block-local literal/address propagation | 0.9686× | 0.9789× |

Both produced the same 5,286,272-frame PCM fingerprint with zero warm missing
frames and zero compilation failures. The observed warm difference is only
1.08% in one constants-then-baseline pair; the earlier roughly 11% Node result
does not transfer to Chrome. A preceding pair with changing external load and
a hidden candidate tab was rejected for performance comparison. Receipts:
`Research/HeavyAcceleration/browser-reverse/comparison.json` and the separately
retained, qualified `browser/comparison-qualified.json`.

CPU0 superregions remained slower after exact state/PCM gates, including guarded
returns, failed-collector memoization and a separately tested canonical-register
variant without eager synchronization. The latter was 12.85% slower in its
matched Node comparison. Lazy dirty-register writeback was approximately flat
and is also rejected as a speed factor.

The surviving private candidate combines literal/address propagation,
block-local dynamic value reuse and direct forward branches to existing normal
block headers. Original target budget guards, region membership and scheduler
remain unchanged. Independent validation passed 63 differential cases through
126 generated modules and a separate full heavy20 PCM/CPU/RAM/LCD/flash/phase
capture against the accepted baseline. Short Stock and Felucca boot/key cases
also matched exactly; these do not establish compatibility or speed for every
FWSC. Candidate module SHA is
`d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87`.

A final actual macOS WebKit Worker comparison used the same heavy120 workload,
15-second warmup, 240 MHz, byte-identical benchmark Worker/worklet and full PCM
fingerprint costs. Separate owned, nonactivating floating windows remained
visible throughout; AC power, thermal state 0 and Low Power Mode off held.

| Generic translator | Warm throughput | Final 20 guest seconds |
|---|---:|---:|
| Accepted baseline | 1.0012× | 1.0196× |
| Candidate with direct forward branches | 1.0548× | 1.0717× |

Both covered 5,286,272 real PCM frames with matching fingerprint `f77e1d42`,
matching LCD fingerprint, zero warm core shortages and zero compilation
failures. The observed warm difference is 5.36% in one candidate-then-baseline
pair. Asymmetric ambient Chrome activity limits small-gain attribution; this is
unpaced core throughput, not a physical audio deadline or listening pass.
Receipt and raw cases:
`Research/HeavyAcceleration/WK-heavy-normalforward/results/comparison.json`.

In a separate 45-second actual WK Worker/AudioWorklet stopped-sequencer/key
pair, mean producer budget was 0.6397 for the candidate versus 0.6692 for the
baseline. First-eligible PCM acknowledgement p95 was 45.56 versus 46.10 ms;
this is not calibrated audible onset. Both matched all 74 control tags and had
small output shortages; changing ambient load also qualifies this comparison.
Receipt: `Research/HeavyAcceleration/Paced-normalforward/results/summary.json`.

The heavy-project 1.3× target remains unmet. The candidate stays private and
has not replaced the installed app's `d4cf83ba…` module. No further phone
installation or universal real-time claim follows from these Mac tests.
