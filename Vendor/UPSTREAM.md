# fm1-emu core provenance

Source: https://github.com/joakimeriksson/fm1-emu
Revision: 7ca5b96c9e828dea5176fc60f0b945abbf442895 (2026-10-16 retrieval).
License: MIT, Joakim Eriksson. See LICENSE-fm1-emu; also included in the app.
Only fm1-isa, fm1-core and fm1-soc are vendored. They have no third-party package dependencies.
No Virtual FM-1/JUCE/GPL engines, firmware binaries or factory sound banks are bundled.
Core/src/lib.rs adapts the upstream machine boot and execution pattern to an instance-based C ABI.
The native panel is newly drawn from the manufacturer product photo, with matrix mappings verified against upstream panel.rs.
