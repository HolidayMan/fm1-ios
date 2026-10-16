# FM-1 iOS prototype

Work directly in this private repository; do not submit Software Factory tasks unless requested.
Read README.md, docs/research.md and docs/verification.md before compatibility or release claims.
Keep external firmware packages, captured audio and Research/ local and ignored. Do not publish source or binaries without authorization.
Native SwiftUI/UIKit frontend, Rust fm1-emu interpreter core; all per-instance emulator calls must stay on one serial worker. No emulation inside the audio callback. No JIT on iOS.
Preserve Vendor attribution and pinned provenance. Firmware boot, audio signal, real-time performance, physical-device usability and App Store acceptance are separate checks.
Use cargo test --workspace --release, simulator tests and appropriate platform build for behavior changes. This repository has no independent review receipt yet.
