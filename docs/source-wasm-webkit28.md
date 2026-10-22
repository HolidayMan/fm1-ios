# Full SLOOP 2.8 source in macOS WebKit — 2026-10-22

The existing complete SLOOP C-source WASM ran in an actual macOS WKWebView
Worker and matched the existing arm64 C reference byte for byte. A bounded
Worker → AudioWorklet PCM graph also ran. Its 23.2 ms queue produced shortages;
46.4 and 92.9 ms queues did not in these individual 30-second trials.

This is the full firmware source described in [source-wasm28.md](source-wasm28.md),
including synthesis, sequencer, controls, UI and 1 MiB flash. It is neither the
PI32v2 binary emulator nor upstream's DSP-only preview. The unmodified module is
898,743 bytes, SHA-256
`a498d730be4c672032463b88ef0881cb3bc7ad360177aeed7d7489d0a2a1dae5`.
No consumer source, firmware build, phone, signing or release was changed.

## Unpaced Worker measurements

Apple M1 Pro, macOS 27.0.1 (26A434), AC power, low-power mode off. Three fresh
instances per scenario share one compiled module. No explicit disposable warmup
precedes these cases; only the first mixed-stress instance is the first measured
instance of that module. Later rows/repeats are not independent cold starts.
Module compilation took 9.82 ms, first instantiation 2.16 ms, first firmware
initialization/flash load 10.96 ms. These are single observations.

Each heavy run contains 2,584 × 512-frame calls, 30.00018 audio seconds at
44.1 kHz; NOTES has 431 calls, 5.00390 seconds. The call budget is 11.610 ms.
Timing encloses the complete source render, including its audio-clock-driven
main loop and firmware drawing; input/copy/QA costs are separately in loop wall
time. Speed is the median audio/render time ratio; percentiles pool all calls
in a row. The Worker clock's observed minimum step was 0.02 ms.

| Scenario | Median speed | p50 / p95, ms | Maximum, ms | Calls over budget |
| --- | ---: | ---: | ---: | ---: |
| FM6 / PHYS / GRAIN stress | 43.43× | 0.26 / 0.32 | 2.76 | 0 / 7,752 |
| Same stress + repeated notes / controls / FX | 41.68× | 0.28 / 0.32 | 1.56 | 0 / 7,752 |
| Three FM6 parts | 51.63× | 0.22 / 0.26 | 0.36 | 0 / 7,752 |
| FM6 / NOISE / GRAIN | 49.05× | 0.22 / 0.28 | 7.10 | 0 / 7,752 |
| NOTES editor / repeated notes | 147.96× | 0.08 / 0.12 | 0.72 | 0 / 1,293 |

Total: 15 runs, 32,301 measured calls, 375.01388 audio seconds. All 18 parity
files per run match the existing native reference: complete int32 PCM, boot and
final flash, final screen, metrics, per-block workload and all 12 logical objects.
Clock, UI-frame, selection, transport, NOTES-page, fade and commit state also
match. Every scenario's first fresh reopen retains all 12 objects exactly and
matches the existing fresh native reopen. Startup flash is preserved. Demand
fixtures and scripted controls are identical to the earlier Node experiment;
this does not search every possible maximum-cost project.

## Paced PCM delivery

Three separate 30-second controls trials deliver 2,584 stereo blocks from a
serial Worker to a real AudioWorklet at 44.1 kHz. The fixed-capacity worklet queue
starts only after full prefill, then returns one producer credit per consumed
512-frame block. The worklet only copies PCM and records counters/hash; no
firmware synthesis or UI work runs in its audio callback. Output gain is zero.

The 2/4-block trials each first render 5.00390 seconds on a disposable instance,
then start a fresh instance of the same compiled module. Warmup maxima were
2.82 / **22.44 ms** respectively; the 4-block trial's disposable warmup had
3 of 431 calls over budget. That is the experiment's largest observed render
call, and its cause was not isolated. It precedes the fresh paced instance. The initial 8-block graph follows the unpaced suite.
These different visibility/warmup conditions prevent a controlled buffer-size
performance ranking.

| Capacity and initial prefill | Missing frames / callbacks | Worker p95 / maximum, ms | Calls over 11.610 ms |
| --- | ---: | ---: | ---: |
| 8 blocks: 92.88 ms | 0 / 0 | 2.06 / 11.76 | 1 / 2,584 |
| 2 blocks: 23.22 ms | **1,280 / 10** | 2.10 / 5.46 | 0 / 2,584 |
| 4 blocks: 46.44 ms | 0 / 0 | 2.00 / 7.12 | 0 / 2,584 |

Each graph consumed all 1,323,008 source frames in order. All generated int32
PCM and the other 17 artifacts still match native exactly. A diagnostic FNV hash
of the consumed real Float32 PCM matches the producer. That hash excludes
inserted silence: the 2-block graph's output timeline therefore **does not**
match native. It inserted 29.025 ms of zero frames and took 30.02921 graph
seconds to consume 30.00018 source seconds. The 4-block queue's observed minimum
before the final drain was 768 frames (17.41 ms). None of these capacities is a
measured touch-to-audio latency; controls are scripted at audio block indices.

The browser reports baseLatency 2.902 ms and outputLatency **160 ms** in all
three graphs. Those reports are separate from PCM capacity, and were not
acoustically verified. The output route was not changed. No physical device
underrun, acoustic latency, listening, iPhone performance or foreground-only
sustained performance is established. A callback's graph-clock increment is
not a wall deadline. The 2/4-block worklet's coarse Date.now maximum callback
intervals were 13 / 12 ms; these are scheduling proxies, not device-drop counts.
The 8-block render outlier's cause and the 2-block shortages' cause were not
isolated. Faster offline synthesis alone does not certify reliable delivery.

## Conditions and reproduction

Native host observations record activation, occlusion, loginwindow, thermal and
low-power state every two seconds and at lifecycle events. The host initially
activates its visible window and keeps a bounded public process activity and
async WebKit request outstanding. All trials later became inactive. The 8-block graph had an occluded interval;
the 2-block graph started inactive/visible and later had several occluded
intervals, ending inactive/occluded. The 4-block graph stayed visible in all
observations after its graph-start marker, starting active and ending inactive.
Initial window-creation occlusion is recorded separately.
The unpaced run was active/visible until near the graph transition. No sampled
loginwindow, low-power state or non-nominal thermal state occurred. This is mixed
visibility evidence, not proof about background/locked operation or battery use.
The process activity ends and loopback server stops when each run finishes.

All sources, PCM, flash and receipts stay in ignored `Research/SourceWasmWebKit28/`.
The original module, synthetic stress fixtures and existing native reference
outputs under `Research/SourceWasm28/` and `Research/NativeSloop/` are prerequisites;
no firmware or native-reference rebuild is needed. From the private repository:

```sh
python3 Research/SourceWasmWebKit28/run.py --label rerun-all
python3 Research/SourceWasmWebKit28/run.py --audio-only --queue 2 --label rerun-audio2
python3 Research/SourceWasmWebKit28/run.py --audio-only --queue 4 --label rerun-audio4
python3 Research/SourceWasmWebKit28/audit.py
```

The runner compiles only the small macOS Swift host, serves a restricted local
file set on an ephemeral 127.0.0.1 port and writes receipts/source hashes.
The audit independently rereads the recorded original runs, compares all
324 saved parity files against native, verifies source snapshots and writes
`summary.json`. It does not automatically audit differently named reruns.
Original receipts: `results/results.json`, `audio2/results.json`,
`audio4/results.json`; environment/host logs and per-call timing arrays accompany
each. Exact executed harness snapshots are `initial8-sources/`, `audio2-sources/`
and `audio4-sources/`. Small later additions improved condition/timing recording
and restricted reference paths; no measured firmware or control logic changed.

There are no consumer behavior changes, so app/core tests and device builds
were not run for this isolated experiment. The research host and all requested
runs completed; the narrower PCM queue shortage remains an explicit failure.
