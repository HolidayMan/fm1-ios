# Full-source SLOOP 2.8 on physical iPhone 12 — 2026-10-22

The complete existing C-source WASM passed exact native-reference comparison on
a physical iPhone 12, iOS 26.6.2 (23G90). The 46.44 ms PCM queue completed its
30-second graph without shortages. The 23.22 ms queue failed with 512 inserted
zero frames across four callbacks. Offline synthesis speed does not certify
low-latency delivery.

A separate development-signed probe, `com.local.fm1.wasmprobe`, was built,
installed and launched with existing local signing. The consumer app and its
saves were not touched. All module/reference/source/audio/flash files remain in
ignored `Research/SourceWasmDevice28/`. This is the complete source module from
[source-wasm28.md](source-wasm28.md), **not** the PI32v2 emulator or DSP-only
preview. Module SHA-256:
`a498d730be4c672032463b88ef0881cb3bc7ad360177aeed7d7489d0a2a1dae5`.

## Physical results

Two fresh instances per scenario shared a compiled module; no explicit warmup
precedes the offline suite. Compilation was 9.98 ms. Clock minimum observed step:
0.02 ms. Each heavy run renders 30.00018 seconds; NOTES renders 5.00390 seconds.
The 512-frame call budget is 11.610 ms. Percentiles pool calls per row; speed is
the median of the two run ratios.

| Scenario | Median speed | p50 / p95, ms | Maximum, ms |
| --- | ---: | ---: | ---: |
| FM6 / PHYS / GRAIN | 41.21× | 0.28 / 0.30 | 7.14 |
| Mixed stress + notes / controls / FX | 40.08× | 0.28 / 0.32 | 1.40 |
| Three FM6 parts | 48.64× | 0.24 / 0.26 | 0.48 |
| FM6 / NOISE / GRAIN | 47.94× | 0.24 / 0.26 | 0.96 |
| NOTES editor / repeated notes, transport stopped | 131.83× | 0.08 / 0.12 | 1.48 |

All 21,534 offline calls stayed within budget. Complete int32 PCM, boot/final
flash, final screen, workload, metrics and all 12 objects match the existing
arm64 C reference byte for byte. State, clock and UI-frame counts match too.
Five fresh instances reload saved flash through the probe's filesystem-backed
origin and retain all objects exactly. Independent on-Mac rereading of the
copied phone outputs verifies **216 exact file comparisons**, including the two
paced runs. The consumer native archive/hardware firmware are different routes;
this does not establish equivalence with them.

A separate stopped-transport probe sends 32 rapid note press/release events,
keeping each pair on the same selected track and checking `playing == 0` in every
acknowledgement. Main → Worker delivery p50 / p95 / max was
0.040 / 0.500 / 1.820 ms; acknowledgement round trip, including render, was
0.730 / 5.380 / 7.220 ms. Maximum render there was 7.04 ms. These synthetic
message timings exclude physical touch, native panel hit-testing, queued audio,
screen presentation and acoustic output.

After a disposable 5.00390-second warmup (maximum 0.62 ms), fresh controls
instances feed an actual AudioWorklet. The callback only copies Worker-produced
PCM and counts/hash-checks it. Output gain is zero during automation.

| Capacity / initial prefill | Missing frames / callbacks | Worker p95 / max, ms |
| --- | ---: | ---: |
| 4 blocks / 46.44 ms | **0 / 0** | 2.44 / 2.74 |
| 2 blocks / 23.22 ms | **512 / 4** | 2.46 / 2.86 |

Both consume all 1,323,008 real source frames in order and match native source
PCM/state. The consumed-source Float32 diagnostic hash matches; it excludes
inserted silence. The 2-block output timeline is therefore not exact: 11.610 ms
of zeros extend graph duration to 30.01179 seconds. Four blocks retain at least
768 queued frames before the final drain. No paced render exceeds 11.610 ms;
the shortage cause was not isolated. Queue capacity is not touch latency.

The browser reports baseLatency 2.902 ms and outputLatency 10.25 ms. The native
session reports Speaker output at 48 kHz; the Web Audio graph runs at 44.1 kHz.
These reports are not acoustic latency or physical device-drop measurements.
The page stayed visible; all native samples after startup were active,
protected data available, low-power mode off and thermal state nominal. Battery
reported 100%; charging state changed during the run. There was no measured
background/foreground recovery, long battery session or listening acceptance.

## Persistence, current handoff and reproduction

A real process termination/relaunch reopens the four-block run's saved flash
from the probe's Documents and checks all 12 objects against native. A subsequent
probe-only reinstall/relaunch repeats that success, confirming its own save
retention. Final reopen: `receipts/reopen-results-final.json`.

The phone is left in the separate **FM1 WASM Probe**, after the successful reopen.
Native status: **COMPLETE — results saved in probe Documents**. Scroll to
**Optional manual listening**, tap **Enable audio**, then **Note 1 / 2 / 3**.
It starts with transport stopped. **Play / stop transport** changes transport;
**Output gain** defaults to 0.25; **Stop audio** closes the manual graph and saves
separate manual statistics. This is a small research interface. The web status
above the manual section retains its initial text after a reopen; the native
completion status and manual section indicate readiness.

The final handoff keeps the screen awake for a bounded 180-second grace; active
manual audio keeps it awake until stopped. Hiding the app restores normal idle
behavior and the page stops manual audio on its visibility event. Those recovery
paths are implemented but were not separately exercised on the phone. Manual
listening, actual touch latency and main-app integration remain human checks.

The probe bundles its assets/references and serves only its own tokenized
127.0.0.1 origin; no Mac server, external service or user saves are needed.
From the private repository, with the existing reference files present:

```sh
python3 Research/SourceWasmDevice28/prepare.py
python3 Research/SourceWasmDevice28/project.py
xcodebuild -project Research/SourceWasmDevice28/WasmProbe.xcodeproj -scheme WasmProbe -configuration Release -destination 'generic/platform=iOS' -derivedDataPath Research/SourceWasmDevice28/build -allowProvisioningUpdates build
# Install/launch only the separate com.local.fm1.wasmprobe on the authorized phone.
# Default launch runs the suite; --reopen reads its saved four-block flash.
python3 Research/SourceWasmDevice28/audit.py
```

Original phone results and full raw outputs: `device-documents/`; compact checked
results: `summary.json`. Signing/install/launch/build receipts are beside them.
The initial full-run receipt inherited a cosmetic `macOS` engine label and a
repeat denominator of three; actual native device/OS receipts identify iOS and
two runs. Handoff-only edits corrected labels, kept the origin/Worker available
after reopen and added idle grace. No measured synthesis/control/queue logic
changed. `first-run-sources-reconstructed/` explicitly reconstructs those earlier
sources; it is not a pre-run signed snapshot. Final handoff source, executable
and asset-manifest hashes are recorded by the audit. No public distribution,
consumer integration or App Store acceptance is claimed.
