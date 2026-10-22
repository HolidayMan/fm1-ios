# Eight source-native instruments

The consumer app selects only complete package size and SHA-256 records backed
by a linked native engine. Updating an instrument requires an exact source pin,
resource verification, native rebuild and signed app update. Downloaded package
instructions are not executed by this flow.

| Instrument | Pinned release | Native kind | Save bytes |
| --- | --- | --- | --- |
| SLOOP | 2.8 | 2 | 1,048,576 |
| Felucca | 1.6.1 | 3 | 1,048,576 |
| X0X | 1.1.0 | 4 | 1,048,576 |
| Melodee (PocketFM INIT bank) | 1.4.5 INIT | 5 | 1,048,576 |
| FM1 Open source preview | V14 | 6 | 536,576 |
| Skiff | 1.4 | 7 | 1,048,576 |
| FoMni | 0.4 | 8 | 1,048,576 |
| Jangada | 1.0.1 | 9 | 1,048,576 |

These are the latest stable releases in their respective primary GitHub
repositories checked on 2026-10-22. Every release tag resolved to its locked
source commit and every downloaded package matched its exact size and SHA-256.
The private check receipt is `Research/NativeReleaseAudit20261022.json`.

The five lock files under `Core/native/` pin sources, resources and package
identities. Preparation and build instructions are in [SLOOP](native-sloop.md),
[family engines](native-family.md), [FM1 Open](native-official-preview.md),
[Skiff](native-skiff.md) and [expansion engines](native-expansion.md).

All engine calls run on one serial worker per instrument. Audio callbacks consume
rendered PCM. State, flash and the official preview's allocations remain isolated
per instance. Save formats remain specific to their engine; the preview's logical
store must never seed a hardware raw-flash save.

All-eight native host release tests passed (87), covering real PCM, display,
controls, irregular render sizes, exact package routing, save reload and instance
isolation. Separate actual old/new library probes verified synthetic edited
Melodee 1.4.3 to 1.4.5 parameters, FM1 Open V13 to V14 projects and Skiff 1.3.2
to 1.4 projects. Original prepared sources and package-specific saves are kept.
Cross-release data-format compatibility does not itself implement host migration.

FM1 Open remains a public-source preview with synthesized demo samples; exact
hardware or online workbench sound parity is not claimed. The Melodee factory banks are excluded by the documented INIT derivation.
Host tests and native compilation establish neither physical-device acceptance
nor App Store rights clearance or approval.
