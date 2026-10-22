# Embedded firmware compiler prototype — 2026-10-22

The prototype runs Clang and LLD themselves as WebAssembly inside an isolated
WKWebView Worker. It compiles real firmware C text and links a new WASM module
locally, persists that result in its own Documents directory, executes it in a
separate Worker and checks PCM, LCD and saved project data against native
references. No remote compilation service or precompiled firmware input is used.
The consumer FM-1 application and its projects are unchanged.

Research source, compiler binaries, source bundles, captures and receipts are
private and ignored under `Research/EmbeddedCompiler28/`. The isolated app is
`com.local.fm1.compilerprobe`.

## Compiler and inputs

Pinned Clang/LLD 22.1.8 use cppstudio-io/wasm-clang-runtime commit
`df1180d80184733c6a01599f76b92b4001d20f87`; licenses, exact asset hashes and
instrumentation are in `compiler/provenance.json`. The selected no-EH compiler,
linker, filesystem runtime, JS and minimal freestanding headers total
55,762,412 bytes. The full C/C++ sysroot is not bundled.

Inputs are SLOOP 2.8, Felucca 1.6.1 and Melodee 1.4.3, with source commits,
resources and copied adapter hashes recorded in `inputs/manifest.json` and
per-firmware provenance. The Mac prepares JSON bundles from raw C files and
previously generated fonts/tables/sample resources. It does not compile or
preprocess the firmware for the embedded compilation path. Native reference
executables are separate diagnostic builds and are excluded from the app.
This is not yet a downloader or general builder for arbitrary GitHub repositories.

Each firmware produces a freestanding no-import WASM engine with fixed 32 MiB
memory. The compiler has its own, larger growable memory. The engine runs in a
serial Worker; a four-block AudioWorklet queue consumes PCM for listening.
Compilation is never performed in the audio callback.

## Simulator gate

Actual iPhone 12 Simulator, iOS 27.0, on the Mac. All three firmware builds
passed before physical-device testing began. The first host attempt failed
because iOS 27 required a scene lifecycle; it did not execute the compiler.
The corrected public UIScene host and failed attempt are retained separately.

| Firmware | C compilation | Linking | Compiler path total | Worker wall time |
| --- | ---: | ---: | ---: | ---: |
| SLOOP 2.8 | 17.055 s | 0.056 s | 17.417 s | 17.487 s |
| Felucca 1.6.1 | 19.827 s | 0.056 s | 20.060 s | 20.077 s |
| Melodee 1.4.3 | 21.648 s | 0.052 s | 21.859 s | 21.876 s |

Each is a fresh compiler Worker, but WebKit/OS code and file caches may be warm.
Compiler total includes loading tool modules, preparing the virtual filesystem,
compiling, linking and copying the result. Worker wall adds Worker bootstrap;
both exclude initial input-bundle loading and subsequent execution verification.
Do not describe these as guaranteed first-install or end-to-end user wait times.

All generated module hashes equal independently compiled WASM-hosted Node
outputs. Twelve complete PCM/LCD/flash/project artifact comparisons passed,
plus a fresh engine instance restoring each saved flash file from disk.
Each smoke renders 192 blocks of 512 frames (2.229 seconds), exercises two notes
and a knob, produces nonzero PCM and commits a save. Melodee uses supported
engine 12; engine 0 is retired in this release. These are deterministic
functional checks, not exhaustive firmware or hardware equivalence tests.

A subsequent simulator listening check loaded the saved generated modules,
verified their hashes, and delivered each same smoke through a real four-block
AudioWorklet graph. All three had zero missing frames and exact producer PCM.
Graph gain was zero; no physical listening acceptance is claimed for these checks.

Simulator receipts:
- `host/runs/simulator-20261022T124654Z/device-documents/results.json`
- `host/runs/simulator-20261022T124654Z/process-memory.jsonl`
- `host/runs/listen-simulator/results.json`
- `host/runs/listen-simulator-final/results.json` (final serialized listening controls, all three passed again)

## Memory measurement boundaries

The simulator's actual compiler WebContent process had a kernel lifetime peak
physical footprint of approximately **574.74 MiB** and an observed resident-set
peak of **850.52 MiB**. Those are different metrics. The native UIKit host had
its own lifetime footprint peak of approximately **123.19 MiB**; separate peaks
are not summed as though they occurred simultaneously. Attribution uses a
baseline and new WebKit descendants of the selected simulator's launchd.
Process rusage is sampled every 100 ms and also exposes the kernel lifetime peak.

Guest linear-memory capacities are recorded separately for Clang, LLD and the
in-memory filesystem. For SLOOP/Felucca/Melodee, the largest observed current
compiler guest plus filesystem capacities were approximately 204/225/260 MiB.
These exclude JS heap, compiled code, WebKit overhead and earlier instances
awaiting collection. They are not whole-process memory measurements.

Two physical Instruments Activity Monitor attempts over Wi-Fi failed to connect
reliably. They do not establish any phone WebContent memory peak. The failure
record is `profiling/device-profile-status.json`; neither the Swift host's own
footprint nor guest memory may be substituted for the missing process metric.

## Physical device status

The first iPhone 12 / iOS 26.6.2 run confirmed actual local compilation and
native-reference parity for SLOOP and Felucca. Observed compiler-path totals
were 24.522 s and 30.449 s, respectively. Lifecycle observations show background
intervals during both cases: these are mixed-lifecycle wall times, not clean
foreground performance benchmarks. Connection loss prevented obtaining the
terminal Melodee result at this stage; no third phone pass is inferred.

The updated probe waits for a foreground, visible page before the suite and
records lifecycle changes throughout. The clean physical rerun is recorded below; the earlier failure/visibility
evidence is retained.

## Clean physical rerun

The final isolated probe completed all three builds on the physical iPhone 12,
iOS 26.6.2. Native lifecycle and JavaScript visibility guards were valid throughout
each measured case. No Instruments recording ran during these measurements.

| Firmware | C compilation | Compiler path total | Input load through verified output |
| --- | ---: | ---: | ---: |
| SLOOP 2.8 | 22.915 s | 23.567 s | 23.833 s |
| Felucca 1.6.1 | 28.783 s | 29.266 s | 29.490 s |
| Melodee 1.4.3 | 31.890 s | 32.367 s | 32.584 s |

All twelve native reference files matched exactly, all three generated module
hashes matched the simulator/Node outputs, and each saved flash reopened exactly
in a fresh engine instance. Each short offline smoke had nonzero audio and no
render block over its deadline. These short checks do not establish maximum-load
performance. Fresh compiler Workers do not guarantee cold WebKit/OS caches.

Compiler guest-plus-filesystem capacity peaks on the phone were approximately
204/225/260 MiB respectively. Full phone WebContent peak remains unmeasured;
the separate UIKit host footprint is not a substitute.

Receipts: `host/runs/device-clean-20261022T134937Z/summary.json` and
`host/runs/device-clean-20261022T134937Z/device-documents/results.json`.

The subsequent physical AudioWorklet check loaded the phone-generated modules
from Documents. All three short 192-block runs matched native PCM exactly with
zero missing frames and zero render blocks over deadline. Gain was zero during
automation; physical listening is left to the user. Receipt:
`host/runs/device-clean-20261022T134937Z/listen-check-results.json`.
The app was then launched in manual `--listen` mode using those same generated
files. Select a firmware, tap Enable audio, then hold Note 12 or Note 16.

Native thermal states during compilation were nominal/fair (0/1); the later
short audio check reported serious (2). No sustained thermal benchmark or
maximum-load claim follows from these short tests.

## Scope

Local source compilation is technically demonstrated for three supported source
adapters. It does not compile arbitrary FWSC binaries, regenerate every upstream
asset on iOS, or prove compatibility with future source releases. App Store
acceptance and integration into the consumer application remain separate work.
