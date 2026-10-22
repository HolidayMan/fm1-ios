# Store build 26: rights and metadata audit

Read-only source/upstream audit performed 22 October 2026. This records evidence
and unresolved questions for the requested free public App Store release; it is
not legal clearance, an archive receipt or App Review approval. No author was
contacted. Earlier preparation documents contain historical gates; the evidence
below supersedes their older sample-license and version observations.

## Current source selection

The native locks select SLOOP 2.8, Felucca 1.6.1, X0X 1.1.0, Melodee 1.4.5,
FM1 Open V14 portable preview, Skiff 1.4, FoMni 0.4 and Jangada 1.0.1. These
are source selections, not proof that a particular signed archive contains them.
The exact archive and its source-delivery package need separate verification.

## Concrete unresolved factory-program rights

Melodee 1.4.5 commit `398ada1e09d864c12f3b778a43e45c7c2a8031b8`
explicitly identifies Casio's 64 CZ-1 factory tones and Sequential's 200
Prophet-5/10 v1.03 programs as third-party data for which it grants no license.
The native source includes generated `melodee_cz1.h` and
`melodee_prophet_factory.h`; compiling the data does not remove this question.
The family lock verifies these generated headers. App attribution alone does
not provide missing rights. Establish applicable distribution rights or replace
these factory banks with appropriately licensed original data before treating
the content as cleared.

Primary evidence: [Melodee licensing](https://github.com/keremimo/melodee/blob/398ada1e09d864c12f3b778a43e45c7c2a8031b8/LICENSING.md),
[CZ-1 provenance](https://github.com/keremimo/melodee/blob/398ada1e09d864c12f3b778a43e45c7c2a8031b8/assets/cz1-factory/README.md),
[Sequential provenance](https://github.com/keremimo/melodee/blob/398ada1e09d864c12f3b778a43e45c7c2a8031b8/assets/prophet5-factory/README.md).
Local copies: `Core/native/licenses/melodee/`, `Core/native/family.lock.json`.

## Corrected historical sample gates

**Hügelton Sample Pack:** Jangada 1.0.1 retained a notice reserving these assets
pending future terms. The rights owner's Felucca commit
`63f88ec18b71c6ed4371d03d6f04dd93f4193ad3` now dedicates `tools/gen_waves.py`
and every sound it generates to CC0 1.0. The generator's executable Python AST,
excluding docstrings and comments, matches the pinned Jangada, SLOOP 2.8 and
Felucca 1.6.1 generators. Differences are license headers and descriptive text;
no synthesis change was found. Preserve this additional grant and provenance
with the release notices. The old unresolved sample-pack gate is superseded
for these matching generated sounds; it is not a grant for unrelated assets.

Verified SHA-256 values:

| Generator | SHA-256 |
| --- | --- |
| Rights-owner CC0 version | `d7af8c153eaff0e735b6db7495b83081d6a1634990e94401dbbdd9b43befdd00` |
| Pinned Jangada / SLOOP | `d574048795c3e3824bdf367e952b855fdad568efc28c55d42029ece9dd46d0fe` |
| Pinned Felucca | `da02f7dceec2ee80d8b6ad3917d1913c4450096bdead1d35b4941e7794a0c402` |

Primary evidence: [pinned rights-owner grant](https://github.com/hugelton/Felucca/blob/63f88ec18b71c6ed4371d03d6f04dd93f4193ad3/LICENSING.md),
[pinned CC0 generator](https://github.com/hugelton/Felucca/blob/63f88ec18b71c6ed4371d03d6f04dd93f4193ad3/tools/gen_waves.py).

**Skiff BREAK/FUNK:** Skiff 1.4 identifies its generated loops, creator workflow
and GPL-3.0-only license. YuE2's published additional creator permission expressly
allows individuals to distribute/license/monetize outputs, including on commercial
platforms; generated outputs do not acquire the model weights' NonCommercial
restriction solely through generation. No model weights are included here.
The earlier lack-of-permission warning is not supported as a specific model-output
blocker by these terms. This does not warrant that generated audio cannot contain
third-party material.

Primary evidence: [Skiff provenance](https://github.com/illuminus5/skiff/blob/c01fa1ed619266d770ea6552b153612e1b77d0a9/assets/breaks/ATTRIBUTION.txt),
[YuE2 additional creator permission](https://github.com/multimodal-art-projection/YuE/blob/main/MODEL_LICENSE)
(checked 22 October 2026, permission dated 16 September 2026).

## GPL and Apple distribution terms

The combined native app and adapters include GPL-3.0 material. Corresponding
source, build scripts and component notices remain required for the applicable
distribution. A public source link and custom EULA alone do not establish that
all Apple distribution terms are compatible with those licenses.

A follow-up reading of Apple's Standard EULA found an explicit carveout for
permissions granted by included open-source licenses, covering copying, reverse
engineering, modification and derivative works. The earlier claim that separate
author permission is necessarily required was too strong. Non-transferable scope,
redistribution and Usage Rules language still create an interpretation risk; this
review does not establish compliance or incompatibility as a legal conclusion.
No new mandatory author-permission gate is imposed solely because code is GPL.
Keep all applicable notices and publish complete corresponding sources and build
instructions for the exact delivered binary. FM1 Open's specific GPL exception
concerns binary SDK linking and is not an App Store exception.

Primary references checked 22 October 2026:
[Apple Standard EULA and OSS carveout](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/),
[Apple minimum EULA terms](https://www.apple.com/legal/internet-services/itunes/dev/minterms/),
[Apple Media Services Terms](https://www.apple.com/legal/internet-services/itunes/),
[pinned Virtual FM-1 GPL](https://github.com/jbschooley/Virtual-FM-1/blob/c52668953231655046ee142d2b3ab4fd2c8ca0b4/LICENSE).

## Branding, privacy and support evidence

The icon is generated artwork without lettering or brand logos. The manufacturer
reference photograph is not packaged (`docs/app-icon.md`). No copied manufacturer
photograph was identified in the reviewed app assets. Rights in product naming
and distinctive appearance still require publisher judgment; an unaffiliated
notice does not itself grant trademark rights.

At inspection, `HolidayMan/fm1-ios` was public, GitHub Issues was enabled and
GitHub Pages was disabled. The existing public support destination is
<https://github.com/HolidayMan/fm1-ios/issues>. The initial remote tree had no privacy policy. PocketFM policy is now published
at https://github.com/HolidayMan/fm1-ios/blob/main/docs/privacy-policy.md and its
URL is configured in the app and App Store Connect.

The reviewed app source has no account, microphone capture, advertising or
analytics integration. Its explicit resource downloads contact third-party
release hosts. The privacy manifest declares no tracking/collected data and
required reasons `CA92.1` (private UserDefaults) and `35F9.1` (elapsed-event
timing). Recheck the final native-only archive and actual network behavior
before entering App Privacy answers; source review is separate evidence.

## Explicit App Store upload mode

`scripts/testflight.py upload` remains internal-only by default. Only explicit
`--distribution app-store` accepts `testFlightInternalTestingOnly` omitted or
boolean false. That mode defaults to the separately prepared private
`~/Library/Application Support/FM1Release/UploadOptions.app-store.plist`;
`--upload-options` can choose an existing options file. Manual signing selections
are preserved. The configured team, upload destination and fixed numbering remain
mandatory. API authentication, private logs and no-account-fallback behavior remain.

The mode only uploads an App Store-eligible build. It does not submit review or
publish the app. Its synthetic tests use no real account/key/upload; implementing
this mode does not resolve the rights questions above or authorize execution.
