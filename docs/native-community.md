# Community instruments — October 27, 2026

Six source-native instruments expand the consumer catalogue from eight to fourteen.
CoralFlower is the requested chord instrument inspired by Telepathic Instruments’
Orchid. These are portable compilations of pinned upstream firmware source, not a
new universal firmware interpreter or a runtime WASM/compiler feature.

| Instrument | Version | Exact source commit |
| --- | --- | --- |
| [CoralFlower](https://github.com/FicusFicusov/CoralFlower) | 0.5 | `b5ceb997be330c8a420958eb8f4e0f4b3ca084c2` |
| [AMB-1](https://github.com/charlesvestal/fm1-amb) | 1.3 | `188b0a42f20a547864e732ae5ea1339d0fbcf395` |
| [GHOULBOX](https://github.com/jasonpersinger/ghoulbox-fm1-dungeon-synth) | 2.4 | `9f2b9a22e456d7fe9552b40f7a1d0c13200913bb` |
| [LOOM-8](https://github.com/charlesvestal/fm1-loom) | 0.9.3 | `92b4bf2c080b0a4172c07e4cf499dd6d557c3f5f` |
| [Hortator](https://github.com/DeadActive/hortator) | 0.25.0 | `9aa704bb9129516ec9d86c056dff5995282093b2` |
| [JIANT FM](https://github.com/juanjiant-bit/JIANT) | 0.9.9-par12 | `527c7e462a1542cbbde2c2cbf6b4bf151954127d` |

## Selection

The October 27 GitHub API snapshot showed JIANT 182 stars, AMB-1 104,
GHOULBOX 72, LOOM-8 49 and Hortator 33. CoralFlower was explicitly requested
and is listed by the community directory with 15 stars. These are interest
proxies, not download counts, active users or a strict top-six ranking.
The [community directory](https://fm1-editor.com/firmware/) and the linked
primary repositories were checked for current versions. Existing eight native
pins remain unchanged; this is an addition, not a claim that all existing pins
are the newest upstream releases.

JIANT uses the STANDARD installer’s tested `0.9.9-par12` build. Its exact source
commit is recorded in the upstream `web/STABLE` and installer CI recipe; an
unreleased README version is not presented as a tested release.

## Native execution and storage

Each engine is compiled from its actual application, DSP, UI and storage code.
Platform I/O is adapted; mutable globals are isolated per instance and exported
symbols are namespaced. The current source-native bridge renders on its serial
worker, never in the audio callback. Source fm1-base CPU2 jobs execute through
its serial fallback in their original continuation order.

New package hashes map to kinds 11–16; unknown or changed packages are rejected
by a native-only Release build. First use still downloads and verifies the exact
public package. Its machine instructions are not executed. Each release keeps
its own complete 1 MiB physical NOR image. Opening another firmware does not
replace SLOOP’s workspace, settings or project library.

CoralFlower settings-log compaction at boot is original firmware behavior; raw
flash bytes can change while settings remain identical. The adapter is compared
against the untouched portable host, including the resulting flash image.

Hortator retains four manual project slots. Stop playback, use SAVE → PROJECT,
select A–D with Knob 1, turn Knob 4 twice and wait for SAVED. The last saved slot
opens after restart. Unsaved edits are not silently written over a named slot.

JIANT retains its original Restore Last OFF default. Enable SYSTEM → RESTORE
LAST to resume edited work, or use JIANT’s own saved projects. Its checkpoint
writes only the private autosave object when that original preference permits.
GHOULBOX similarly checkpoints its private current-work object. SLOOP-specific
file tools are not advertised for these six unrelated storage formats.

## Preparation and source delivery

Exact source, package, generated-resource, submodule and notice pins are in
`Core/native/community/community.lock.json`. Use the build Python environment
with the upstream font/resource-generation dependencies, then prepare explicitly:

```sh
python3 Core/native/community/prepare.py "$PWD/Research/NativeCommunityOct27"
export FM1_NATIVE_COMMUNITY="$PWD/Research/NativeCommunityOct27"
```

Also set the five existing native source variables documented in
[native store builds](native-store-build.md). The compiler never fetches source,
uses changed pins, or falls back to runtime emulation. Source checks run before
any generator. Generated resources have separate fingerprint checks; Python
bytecode and machine-local caches are not source inputs.

AMB-1 and LOOM-8 use pinned fm1-base and felucca-bsp submodules. Their URLs and
immutable commits are included in the source-release manifest. App sources,
portable adapters and build recipes are included in the corresponding source
archive; upstream trees are acquired separately at those exact pins.

## Credits and assets

CoralFlower, GHOULBOX, Hortator and JIANT retain their GPL-3.0 notices; AMB-1 and
LOOM-8 retain MPL-2.0 file notices and their dependency notices. Complete texts
and component credits are bundled in `NOTICE-native-community`,
`LICENSE-native-community` and `THIRD-PARTY-native-community`.
CoralFlower’s disabled CZ/QUAD factory banks are not linked.

Hortator’s old asset paragraph is qualified by the original Hügelton author’s
[pinned CC0 grant](https://github.com/hugelton/Felucca/blob/440e62ce8a33d9bb285ab6bbca9a0fd50e459648/LICENSING.md).
The procedural generator has identical executable syntax to the pinned licensed
original. The exact grant, generator hashes and comparison evidence are retained
in its descriptor. No new author permission or third-party contact was inferred
from a fork’s unilateral licensing change.

## Verification boundaries

Host checks exercise exact package classification, real PCM/LCD output,
non-silent interleaved-instance isolation, original NOR preservation and storage
round trips. Additional source-specific tests cover real save controls,
fresh-process restoration, malformed-storage rejection, and original autosave
preferences. CoralFlower additionally has untouched-host parity and ASan/UBSan
checks. Private receipts and screenshots are under `Research/Community29/` and
the native preparation directories. Platform build, simulator user journeys,
TestFlight readiness and physical-iPhone acceptance are separate checks.

## Build 29 verification receipt

All fourteen linked native engines passed the Rust workspace: 91 tests, no
failures. The Python checks passed 30 tests. iOS simulator units executed 113
cases: 106 passed, seven explicit performance/stress opt-ins skipped, no failures.
One end-to-end iPhone 12 simulator case passed all six real public downloads,
selection, keys/HOME, pause/resume, capability gating and CoralFlower reopening
after app relaunch. The signed device archive passed the native-only resource,
symbol/framework and privacy-manifest audit.

The staged read-only owner-workspace copy retained all 24 file hashes, and both
test simulators were shut down. No physical phone workspace was modified.
Private detailed receipts are `Research/Community29/platform-qa-receipt.md` and
`Research/NativeCommunityOct27/community-host-receipt.json`. TestFlight
availability requires a separate processing/group-assignment readback; device
listening, latency and saved-project acceptance remain for the owner to test.

Panel LED masks are retained, but hardware PWM/dimming/breathing timing is mapped
to portable-host brightness rather than simulated cycle by cycle. In particular,
JIANT intentionally illuminates its available keys as idle guides; those guides
are not evidence of held notes or a stuck key.
