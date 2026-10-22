# Binary SLOOP DSP kernel to standalone WASM — 2026-10-22

A bounded binary-translation experiment succeeded on Mac. Twelve actual PI32v2
instructions from SLOOP 2.7.1 FWSC, at `0x0200a812..0x0200a836` (end exclusive),
were decoded and lowered directly to WASM. No SLOOP C source was compiled or
used to generate the implementation. The 983-byte module has no imports, CPU
runtime calls or guest instruction dispatch. Registers are WASM locals; an
explicit input/output state record supports differential verification.

The kernel reads two signed 16-bit table entries and interpolates by phase.
The original 2 KiB table and decoded instruction bytes were independently
checked against the unpacked FWSC image. Runtime captures use an instrumented
CPU1 single-step window; they are diagnostic inputs, not an unchanged full-system
scheduler performance measurement. Zeroing the first 128 kernel results changes
the ensuing PCM fingerprint, while the pre-note fingerprint agrees, supporting
that this executed kernel contributes to audio in this fixture.

## Verification

- 128 real invocation states match their captured live exit states exactly.
- 20,608 cases per table, across original, signed-extrema and seeded-random
  tables: 61,824 differential checks match the original CPU interpreter.
- Compared state includes all 16 registers, arithmetic flags, PC and the
  additional explicit CPU fields; input records and image remain unchanged.
- Root review reran the verifier and independently checked emitted instruction
  bytes and captured table against the image. Scope is these 12 instructions,
  not full firmware, hardware or universal ISA correctness.

## Same-runtime microbenchmark

Apple M1 Pro, macOS arm64, Node 26 / V8 14.6. Both the reference interpreter and
translated kernel run as WASM in the same Node process. The reference uses
original `Cpu.step` with cached decoding. Nine alternating-order timed samples
follow warmup; each sample invokes 20,608 inputs twenty times (412,160 calls).
Both paths load/store explicit state and consume an output checksum. Loading,
WASM compilation and instantiation are excluded from execution timing.

| Path | Median batch | Per invocation |
| --- | ---: | ---: |
| Original cached-decoding interpreter | 59.369 ms | 144.04 ns |
| Standalone translated kernel | 4.570 ms | 11.09 ns |

Independent rerun ratio: **12.99x**. This compares against the interpreter,
**not the existing optimizing WASM region translator**. It does not demonstrate
a 13x whole-emulator improvement, sustained audio performance or iPhone speed.
Generated code is 983 bytes; table, host harness and memory are additional.

## Implication

Direct binary-to-WASM lowering without a virtual CPU executor works for this
real arithmetic kernel. Remaining whole-program issues include control-flow
recovery, indirect targets, runtime-loaded code, hardware access and dual-core
scheduling. This experiment does not establish that most firmware cost can be
removed, or that the existing translated backend would benefit similarly.
The next useful comparison is the same captured kernel against that backend,
followed by a larger complete DSP loop if it shows a meaningful benefit.

Private source, input/output artifacts, receipts and reproduction files are in
`Research/BinaryKernelWasm/`. Consumer application, device and user saves were
not changed. No source or firmware was published.
