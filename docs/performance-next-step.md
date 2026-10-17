# Real-time optimization on iPhone 12

The retained baseline at `70b25ce` was CPU-bound for Felucca 1.6.1 and SLOOP 2.7.1. Their physical iPhone 12 mean render budgets were 130.6% and 121.5%; actual output sample shortages were 24.24% and 19.54%. The source ring exposed the shortages but could not compensate for insufficient interpreter throughput.

## Reproduction and profiling

A dedicated iPhone 12 simulator reproduced the bottleneck: 112.09% / 109.23% mean render budgets and 12.04% / 11.16% output shortages for Felucca / SLOOP. This is an iPhone 12 device configuration running on the Mac's M1 Pro CPU, not emulated A14 performance. Controlled runs use frozen Release binaries and identical firmware/initial flash snapshots. See `performance-lab.md` for methods and results.

Instruction-level profiles attributed the main costs to operation dispatch, retirement bookkeeping, block lookup and event-boundary checks. Roughly 84–85% of CPU0 instructions in the heavier firmware ran in the main context; interrupt audio processing was only about 11–13%. Smaller host execution batches and simple idle-loop reductions did not solve the bottleneck. A generic C threaded interpreter also failed to produce a sufficient gain by itself. Host PGO improved throughput modestly, but its profiles did not match the iOS target and were not shipped.

## Retained implementation

The optimized build contains 768 statically compiled hot-block kernels selected from local Stock, Felucca and SLOOP profiles. Constant decoded operands let the compiler simplify instruction dispatch and register access across a block. They execute from ordinary signed application code: no runtime code generation, executable-memory mutation or JIT.

Binding checks the complete decoded block: PC, length, every descriptor field and instruction metadata. The full block must fit before the next observable event. Unsupported operations, MMIO and tracked code-memory writes return to the reference path without consuming the unexecuted instruction. Register/flag state, guest ticks, interrupt boundaries and shared CPU scheduling retain reference semantics. RAM-resident code is excluded from generated kernels and stays entirely on the original Rust execution path, avoiding C fallback overhead. Unmatched firmware and changed blocks use the normal interpreter.

Generated firmware-derived headers, captures and manifests stay in ignored `Research/Generated`; only the generic generator and execution infrastructure are tracked. Build verification rejects corrupt headers and changed generator/interpreter sources. A missing generated header produces the generic interpreter, not an unverified optimized build.

## Acceptance and remaining work

The first host smoke comparison reduced Felucca and SLOOP wall time by approximately 46% and 45%, with exactly matching PCM, LCD and flash fingerprints for all three firmware fixtures. Stock was approximately unchanged. The final RAM fallback also removes the initial Stock regression. These are host measurements. Final build 4 passed three minute-long steady audio scenarios on both the simulator and physical iPhone 12, with zero core/output shortages in every measured phase; full timing and limitations are in `verification.md` and `performance-lab.md`.

Correctness checks cover all generated kernels against reference execution, descriptor mutation rejection, budget/prefix boundaries, memory side effects, panic containment and C/Rust ABI offsets. Sustained audio tests separately check repeated attacks, chords and encoder activity after warmup, requiring zero additional core/output sample shortages. The original 25-second startup-inclusive comparison remains separate.

A short benchmark cannot establish long-session thermal behavior, every patch, full polyphony, touch-to-sound latency or listening acceptance. Other firmware releases retain compatibility fallback but need their own profiles and validation before equivalent performance can be claimed. No guest-clock reduction, sample dropping or approximate replacement of firmware synthesis is used.
