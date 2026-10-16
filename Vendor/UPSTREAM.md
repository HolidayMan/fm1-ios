# fm1-emu core provenance

Source: https://github.com/joakimeriksson/fm1-emu
Revision: 7ca5b96c9e828dea5176fc60f0b945abbf442895 (2026-10-16 retrieval).
License: MIT, Joakim Eriksson. See LICENSE-fm1-emu; also included in the app.
Only fm1-isa, fm1-core and fm1-soc are vendored. They have no third-party package dependencies.
No Virtual FM-1/JUCE/GPL engines, firmware binaries or factory sound banks are bundled.
Core/src/lib.rs adapts the upstream machine boot and execution pattern to an instance-based C ABI.
The native panel is newly drawn from the manufacturer product photo, with matrix mappings verified against upstream panel.rs.

Local interpreter changes (2026-10-17): borrow cached micro-ops during execution,
use the existing RAM code-write counter for native cache validation, inline checked
RAM accessors, and specialize common integer operations. Code-cache storage is
bounded by both operation and block counts. iOS still explicitly disables JIT.
Regression tests compare flags and registers across integer specializations,
instruction counts and due-tick/budget boundaries, and code invalidation for tracked
and untracked buses. Upstream MIT attribution and the pinned source revision above
remain unchanged.

Pure register-add/branch pairs may share one dispatch only when both instruction
ticks fit before the bus's next event; otherwise execution uses the ordinary
per-instruction path. No audio samples, guest instructions or clock cycles are
dropped. Experimental traces, static multi-operation handlers and polling-loop
reductions were not retained because they did not improve total workload time
consistently against this smaller implementation.
