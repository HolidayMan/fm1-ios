# Remaining real-time limit on iPhone 12

The 2026-10-17 Release measurements confirm that the generic interpreter remains CPU-bound for Felucca1.6.1 and SLOOP2.7.1. The source ring fixes production scheduling and exposes actual shortages; it does not make insufficient CPU throughput disappear. Current measured render budgets are approximately131% and121%, respectively, before allowing safety margin or full polyphony. Stock averages48%, with rare output shortages in the short test.

## Evidence and rejected approaches

The first retained interpreter changes improve Mac throughput by roughly6–8% lower elapsed time in the final comparison over the original prototype with unchanged deterministic audio output. Subsequent XIP traces, large generated static handlers, pure scan-loop reductions and pointer/code-layout experiments were benchmarked and rejected when they did not produce a repeatable net gain against that smaller checkpoint. Correctness tests alone are insufficient grounds to retain performance complexity.

Instruction-level profiling identified the main remaining costs inside run_fast: fast-op dispatch/operations (~34%), retirement bookkeeping (~12.5%), block lookup (~8.4%), iteration (~6.4%), tick handling (~6.1%) and careful-path selection (~5.4%). These are Mac profile observations, not direct iPhone instruction attribution. The exact local profiles and rejected experiments remain private under /tmp; they are not shipped.

## Concrete next architecture experiment — not implemented

Prototype a statically compiled direct-threaded hot-op interpreter, with the current Rust interpreter as a correctness fallback. This is a different dispatch architecture, not executable-code generation/JIT. Evaluate whether a small C backend using compiler-supported threaded dispatch is preferable to Rust's central enum match, before committing to a complete backend.

Keep CPU registers, flags, guest clocks, event boundaries, code-write invalidation and shared CPU scheduling semantically identical. Fall back at unsupported operations, MMIO/interrupt boundaries and unproven paired-instruction cases. Do not reduce the guest clock, skip control scanning heuristically or replace firmware engines with approximations.

The experiment is successful only if it produces a substantial measured gain against the retained baseline, unchanged audio/LCD/flash fingerprints, differential register/flags/tick/MMIO results, bounded cache memory, and physical Release output measurements with useful headroom on Stock, Felucca and SLOOP. More complex firmware, full polyphony, long sessions and thermal behavior then need their own matrix. A short test with nonzero audio is not a quality pass.
