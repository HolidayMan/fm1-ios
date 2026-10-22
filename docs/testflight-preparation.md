# TestFlight preparation

### API-key upload helper

`scripts/testflight.py` uses Python's standard library and the installed
`xcodebuild`. It requires an App Store Connect **team API key**, with access to
this app and uploads. Team API access activation, key creation and Apple roles
are separate account setup; the helper never creates keys or reads their bytes.

Keep the downloaded `.p8` and configuration outside this repository. The default
configuration is
`~/Library/Application Support/FM1Release/appstore-connect.json`, containing only
`key_path` (absolute path to the `.p8`), `key_id`, `issuer_id` and `team_id`.
Set the containing private folder to mode `700` and both files to `600`.
Enter these values locally; do not put the key or configuration in chat or Git.

```sh
python3 scripts/testflight.py validate-config
python3 scripts/testflight.py upload \
  --archive build-device/Release/FM1.xcarchive \
  --export-path Research/TestFlight/release-export \
  --log Research/TestFlight/release-upload.log
```

The helper rejects an archive whose bundle, team or version/build differs from
the configured team and current app sources. It also compares the archived app's
identity and requires a device build. Continue the separate signature, source
freeze and test verification before uploading. It uses the existing
`~/Library/Application Support/FM1Release/UploadOptions.internal.plist`, which
keeps manual signing certificate/profile selections outside the repository and
enforces internal-only distribution and fixed build numbering. `--upload-options`
can select another locally prepared options file with those same constraints.

The configured Developer-role key can authenticate uploads; it does not provide
the distribution certificate/profile creation or cloud-signing authority needed
by automatic export in this setup. An Apple Distribution certificate with its
matching local private key and an App Store provisioning profile must first be
prepared using an appropriately authorized account. The private options file
selects those existing signing assets. This is a one-time setup for the current
assets, not automatic renewal: certificate/profile expiration, revocation or a
changed signing identity requires explicit maintenance.

Authentication always supplies `-authenticationKeyPath`, `-authenticationKeyID`
and `-authenticationKeyIssuerID`, with `-allowProvisioningUpdates`. There is no
Apple Account fallback when the configuration is absent or an upload fails.
Validation displays redacted metadata; upload diagnostics are redacted and saved
to a new owner-only log. A successful command confirms upload completion only;
Apple processing, compliance, group assignment and TestFlight availability still
need their own readback.

Read-only readiness check, 2026-10-19. No Apple upload, app-record creation,
tester invitation, agreement acceptance, certificate creation or account change
was performed. This is preparation, not distribution clearance or an upload receipt.
At that baseline check the Projects/Files implementation was still in progress;
the subsequently validated local candidate is recorded below.

### Local candidate after that baseline check

The subsequent 0.6.0 (17) candidate implements the native finish-tinted glass
window and first SLOOP project/sample/WAV workflows. Core86, initial Swift77
(seven opt-in skips) and final17 affected tests passed; four simulator UI cases
are satisfied across the main run and targeted retest. The clean archive is
`build-device/Glass17/FM1.xcarchive`, with dSYM and verified Apple Development
signature. Its `get-task-allow=true` means it still needs distribution re-signing;
it is not a validated TestFlight upload. Full receipt and exact limits are in
`Research/Projects17/device-archive-receipt.json` and verification.md.

Prepared local-only `Research/TestFlight/ExportOptions.internal.plist` uses
`method=app-store-connect`, `destination=export`, manual build numbering and
`testFlightInternalTestingOnly=true`, checked against Xcode27.1 help. It has not
been executed. No account/identity/rights gate below is marked resolved by a local
archive. Research WASM resources remain in that development bundle; no uploader
or App Store Connect validation has been invoked.

## Recommended route

For the owner's remote phone updates, use **TestFlight Internal Only**, once the
account, rights and artifact gates below are resolved. An eligible App Store
Connect user can install updates in TestFlight away from the development Mac;
the phone does not need a local cable connection for this distribution route.
An internal-only build cannot later be submitted to external testers or customers;
make a separate eligible upload if that scope changes. Internal testing supports
up to 100 App Store Connect users with app access, and builds expire after 90 days.
[Apple: internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

External testing is a different path: up to 10,000 testers, with the first external
build requiring TestFlight App Review. Public App Store release is a further,
separate submission. Do not add arbitrary people as App Store Connect team users
just to avoid external beta review.
[Apple: TestFlight](https://developer.apple.com/testflight/)

## Verified local baseline

| Check | Evidence and limit |
| --- | --- |
| Toolchain | Selected Xcode 27.1 (27A9275). No archive/build was run by this check. |
| Account presence | Xcode has one configured account and a cached Individual team marked `isFreeProvisioningTeam=false`. This supports a paid-team path; current membership, role and agreements still require live verification. |
| Reachable signing | One valid Apple Development identity; no local Apple Distribution certificate found. No private keys or credential contents were read. |
| Provisioning | Three cached profiles: another app's development and App Store-style profiles, plus a development wildcard, expiring October 2027. No FM1-specific distribution profile was found. Another app's profile cannot sign FM1. |
| Existing clean artifact | `build-device/StorePrep16/Build/Products/Release-iphoneos/FM1.app`: 0.5.0 (16), `com.local.fm1.instrument`, iOS 17 minimum, development `get-task-allow=true`. It is not a TestFlight distribution artifact. |
| Source settings | Automatic signing, no team committed in `project.pbxproj`; explicit team is needed for archive/export. `App/Info.plist` remains 0.5.0 (16) at inspection. |
| App Store Connect | A fresh browser visit reached the login page with `authResult=FAILED`. No authenticated FM1 record, role, membership or agreement state was observable. No login credentials were entered. |
| Upload automation | No repository Fastlane/workflow/ExportOptions/uploader configuration found. Transporter.app is not installed. Xcode Organizer is already a supported upload route; neither CI nor Transporter is a prerequisite. |
| Last phone delivery | `verification.md` records 0.4.2 (15) as the last delivered build; 16 was not installed there. This check did not contact or inventory the phone. |

The missing local distribution identity is **not proof that distribution is
impossible**: Xcode supports cloud-managed signing. Confirm the authenticated
team's permission to use that service before creating any new certificates.
[Apple: distribution and cloud signing](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/)

## Gates before any upload

1. **Human account checkpoint.** The owner signs into App Store Connect and
   confirms the intended non-free team, active Developer Program membership,
   app access/role and agreement status. Do not accept agreements automatically.
   App creation requires Account Holder/Admin/App Manager; uploading supports
   Developer as well. An existing FM1 record is currently unknown, not proven
   absent. An Account Holder must resolve any required latest agreement.
   [Membership](https://developer.apple.com/help/account/membership/programs-overview/),
   [new app prerequisites](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app),
   [upload roles](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
2. **Choose identity and migration.** Confirm app name, bundle ID and tester Apple
   Account. Keeping the existing bundle/team identity is the candidate for an
   upgrade; changing the bundle creates a separate app sandbox. Before trying the
   development-to-TestFlight transition, preserve owner projects/packages/settings
   and record a retention check. Do not promise data retention from matching IDs
   alone, uninstall the current app, or reset its data to make installation work.
3. **Resolve the rights scope below.** Uploading to Apple is a new distribution
   boundary. Internal-only access is not an asset license, a blanket GPL exception
   or public App Store clearance. Rights decisions must identify the exact archive,
   recipients and terms. Do not substitute/strip engines or samples silently.
4. **Freeze the actual candidate.** Finish Projects/Files work, independent review
   and appropriate simulator/device gates. Root owns the serial Release device
   archive. Record source/native archive hashes, notices, resource inventory,
   version/build and privacy manifest. The last development bundle still contains
   research WASM assets; audit reachable code and packaged assets for the intended
   native-only beta. A removed menu is not an artifact audit.
5. **Prepare distribution signing and validate.** Use the selected team and an
   explicit FM1 App ID/profile or cloud-managed equivalent. Export/archive must
   have correct distribution entitlements, no XCTest host, expected resources,
   valid signatures and matching dSYMs. Run Organizer Validate App and keep its
   result separate from Apple processing/review and actual phone acceptance.
   Current Xcode 27.1 meets the published iOS build toolchain floor; successful
   validation is still required for the exact candidate.
   [Apple: validation](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/),
   [supported uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
6. **Encryption and privacy answers.** Current plist declares
   `ITSAppUsesNonExemptEncryption=false`; verify that against final dependencies
   and actual HTTPS/platform-crypto usage rather than assuming no encryption.
   Resolve any Missing Compliance state. The local manifest is not a final privacy
   audit. TestFlight feedback/crash collection by Apple must be distinguished from
   the app's own collection. Public privacy/support URLs and full store metadata
   remain public-release gates; internal beta setup does not require completing
   all public screenshots/pricing/marketing work first.
   [Export compliance for beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/),
   [encryption determination](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

## Eight-engine rights/content review

All eight compiled routes and the shared app/wrappers include GPL-3.0 material.
Retained notices do not by themselves complete corresponding-source obligations
or settle compatibility with Apple's distribution terms. Review the complete
combined work and applicable rights, not only each engine's short SPDX label.
This document records unresolved repository gates; it does not declare all GPL
apps categorically prohibited or decide legal compliance.

| Pinned engine | Recorded content issue / required review |
| --- | --- |
| SLOOP 2.8 | GPL application/wrapper; CC0 samples and MIT/Apache/OFL components have retained notices. Check exact linked assets and source delivery route. |
| Felucca 1.6.1 | GPL application plus MIT engine submodule; verify the pinned generated sample/font/icon inputs and their own terms. |
| X0X 1.1.0 | GPL application and adapted platform; verify generated resources/component notices in the exact archive. |
| Melodee 1.4.3 | **Unresolved:** pinned `LICENSING.md` explicitly grants no redistribution license for the Casio CZ-1/Sequential factory programs. Generated compiled data still counts in the inventory. |
| FM1 Open V13 Preview | Public browser source compiled; proprietary SDK binary is neither linked nor included. GPL with SDK exception does not itself grant Apple-platform distribution rights for unrelated components. Keep preview/hardware and synthesized-demo-sample disclosures. |
| Skiff 1.3.2 | **Unresolved:** BREAK/FUNK YuE2 output provenance is retained; upstream individual-creator permission claim does not establish every third-party right. Review generated audio and GPL/sample/font components. |
| FoMni 0.4 | GPL app/platform; Chordian sound/rhythm data CC0, fonts OFL. Verify those exact inputs and notices. |
| Jangada 1.0.1 | **Unresolved:** pinned licensing reserves the Hugelton Sample Pack pending published terms, although the generator uses those samples. Other CC0 samples do not clear that separate bank. |

Local evidence: `App/NOTICE-native-{sloop,family,official-preview,skiff}`,
`Core/native/licenses/`, source/resource lock files and
[existing store gates](app-store-preparation.md). No author was contacted.

For **internal TestFlight**, establish permission/source obligations for the
intended Apple-mediated beta and clear or explicitly resolve each restricted
asset before upload; maintain an eligible team-only tester scope. A successful
upload is not that clearance. For **external beta/public App Store**, repeat the
rights check for that scope and additionally satisfy beta/public review, branding,
truthful metadata, support/privacy URLs and final consumer acceptance. Existing
local private tests do not establish either distribution scope.
[Apple intellectual-property requirements](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)

## Concrete handoff after clearance and authorization

1. Reuse a verified FM1 App Store Connect record or create one with the approved
   identity. Create no duplicate record speculatively.
2. Select the frozen archive and upload using **TestFlight Internal Only**. Keep
   manual group assignment so processing does not silently distribute a new build.
3. Wait for processing, resolve compliance, create/select an owner-only internal
   group and enter useful What to Test text. Verify the owner is an eligible user
   before assigning the build. Group assignment can send invitation emails and is
   an external action requiring explicit task authorization.
4. Owner accepts in TestFlight on the remote phone, installs without an uninstall,
   opens the expected version/build and checks project retention, Projects/Files,
   each included engine's audio and recovery. Record install/retention/listening
   acceptance separately; keep the safe backup until this succeeds.

No API keys, passwords, private certificates/keys, tester emails or device IDs
belong in this file, Git or the release notes. Sanitized local inspection evidence
is under ignored `Research/TestFlight/`. No uploader credential was sought.

## Authorized TestFlight attempt — 2026-10-19

The owner explicitly authorized uploading for remote personal testing, with
public App Store release still deferred. The preparation baseline above is
historical; this section records the actual attempt.

The 0.6.0 (17) archive was reverified: strict signature passed, all recorded App
source/resource hashes match, executable SHA256 matches the frozen receipt,
and dSYM is present. No firmware packages or test bundles ship. Research web
resources still ship in this development candidate; the final native-only
artifact/content gates above have not been silently waived.

A real distribution export was attempted with the existing internal export
options and `-allowProvisioningUpdates`. It failed before producing a
TestFlight IPA: Xcode reports **No Accounts**, plus no iOS App Store provisioning
profile for `com.local.fm1.instrument`. Live Xcode Settings > Apple Accounts
shows no signed-in account, overriding the older cached-account inventory.
The account sign-in sheet is open. App Store Connect is at the unauthenticated
sign-in page. No credentials, MFA codes or private keys were read or entered.

Owner participation now required: sign in on this Mac in **both Xcode Settings >
Apple Accounts and App Store Connect**, including personal MFA confirmation.
Do not send passwords/codes in chat. If an updated agreement or membership action
appears, the owner must review it; none was accepted. A browser login alone does
not supply Xcode's distribution credentials.

Prepared under ignored `Research/TestFlight/`:
- `attempt-17.json`: exact archive check, failed-export receipt, upload=false.
- `export-17.log`: actual export failure; local only.
- `app-record-draft.json`: proposed name, existing bundle ID, SKU and owner-only
  group; must look for an existing record before creating one.
- `beta-description.txt` and `what-to-test-0.6.0.txt`: reusable beta metadata and
  a retention/audio/project/sample/WAV test checklist with honest limitations.
- `ExportOptions.internal.plist` and `UploadOptions.internal.plist`: local export
  and upload options, internal-only and manually assigned, checked against local
  Xcode help. Upload options have **not** been executed.

After authenticated access is available, verify team and existing app record,
resolve the recorded content/artifact scope, finish distribution signing, then
validate/upload. Assign only the owner after Apple processing/compliance succeeds.
Do not uninstall the phone app to force installation. Matching team/bundle is the
intended update path but actual TestFlight save retention still needs acceptance.

No App Store Connect record, profile/certificate, tester/group or agreement was
changed. No build was uploaded, public release submitted, phone contacted or
source pushed by this attempt. The exact failure is authentication/provisioning;
no paid membership failure, Apple rejection or rights clearance is inferred.

## Authenticated continuation — 2026-10-19

The owner completed both sign-ins and explicitly requested proceeding. The same
archive 0.6.0 (17) exported successfully using automatic App Store Connect signing.
The exported IPA passes strict signature checks: get-task-allow=false,
beta-reports-active=true, exact team/application identifier, no provisioned-device
restriction. Receipt: Research/TestFlight/distribution-17.json.

FM-1 Instrument was created in App Store Connect as app6824659753 using the
existing com.local.fm1.instrument identity, English (US), SKUfm1-ios-instrument.
The previous list contained Replay Mirror only; no duplicate FM1 record was found.
A real internal-only upload exited0 and reports Upload succeeded / uploaded package
is processing. Log: Research/TestFlight/upload-17.log. Processing and installation
availability are still separate from upload success.

An internal Owner Beta group was created with automatic distribution disabled.
Only the existing Account Holder was selected as tester; no new team user or role
was created and no external testing group or public link was enabled. Keep tester
contact details in Apple, not source documentation. Final group assignment and
Apple processing status are recorded in the receipt when verified.

This is the explicitly authorized private owner beta of the development candidate,
not public-release clearance. The eight-engine/source/bank rights and final
native-only packaging/public metadata gates above remain unresolved; upload
success does not settle them. No agreement was accepted by the agent, no public
review/release was submitted, and no phone installation or retention/listening
acceptance has been claimed. No app source/engine/content change was made in this
upload continuation.

### Final beta availability

Apple processing completed and the exact0.6.0(17) build showed **Ready to Test**.
The saved What to Test text describes actual features, limits and save-migration
checks. It was assigned to Owner Beta; the build details show that group as
Internal with one tester. The group verifies1tester/1build and the owner status
**Invited** (19October2026,22:40 Europe/Warsaw). No external group/public link was
created. Invitation state is verified; actual email delivery, acceptance,
installation and musical-project retention on the remote iPhone are not.

Owner handoff: open Apple's TestFlight invitation on the iPhone, accept it in
TestFlight and install FM-1 Instrument0.6.0(17) without first uninstalling the
existing app. The identical bundle/team is retained. Check current work before
saving over it and report any missing projects. The private beta is available;
this is not App Store public-review approval or a public release.

Final iOS Builds readback: **Testing**, Owner Beta, Invitations1. Screenshot:
Research/TestFlight/testing-0.6.0-17.png. Phone installations are not yet verified.

## Lighting update — 0.6.1 (18)

The owner approved the soft-halo option and requested visible dim illumination
on Purple. Local native verification and source/artifact receipts are under
Research/Keylight18/.18finalunitcases passed; the two real HID touch UIcases
passed before a brightness/recess-only adjustment with identical input geometry.
The signed archive preserves all engines, package IDs and saves; only the panel
renderer/version differ from17. Native core archives match17 exactly.

Internal-only upload exited0 after Apple metadata processing delayed the uploader
for several minutes; it was not retried in parallel. App Store Connect app6824659753,
build b70879ea-d1e9-40fa-9889-fbb224b395a9, reached Ready to Test. A separate
export of that exact archive has verified distribution signature, get-task-allow=false,
beta-reports-active=true and the same team/application identity. Its hash is a
separate-export hash, not a claim about exact uploaded bytes. Final group assignment
and Testing readback are recorded in Research/Keylight18/verification.json.

What to Test describes the LED change, firmware-controlled dim/off/active states,
unchanged audio/geometry and retention check. No public release or new physical
phone acceptance is implied. Existing public asset/source/packaging gates remain.

## Compact chrome update — 0.6.2 (19)

The external top/side surfaces return to small plain controls on black. The side
column is lower, clears physical corners and reuses the landscape safe-area gutter.
Colored key finishes have tailored, smaller halos and recesses; Black's three
native lighting captures are byte-identical to18. Unit20cases and4distinct UI
cases passed on iPhone12/iOS27.0; the initial undersized plain-label touch regions
were fixed and retested without weakening assertions.

Signed archive, dSYM, source freeze and strict signature were verified before
internal-only upload. Native core hashes and all app sources except chrome,
panel optics and version match18. Distribution receipt and final Apple/group
readback are under Research/Chrome19/verification.json. Only Owner Beta is in
scope; no public release, other tester group or physical phone acceptance.

19 upload exited0 (Upload succeeded/EXPORT SUCCEEDED). A separate distribution
export of the same archive passed strict signature, release entitlements and
team/application identity checks. After upload the browser session expired;
owner re-login was requested. Server Ready to Test, beta notes and Owner Beta
assignment remain unverified/pending; no Testing/phone availability claim.

After owner re-login, build19 (4e9c2a2a-bd92-4b38-b310-6e8311bcd3f4)
was verified Ready to Test. Beta notes were saved and only Owner Beta was added
(Internal,1 tester). Final iOS Builds readback shows0.6.2/19 Testing, Owner Beta,
1 invitation. Screenshot/receipt: Research/Chrome19/testflight-testing.png and
verification.json. No other group modified; physical install/acceptance unverified.

## Spacing update — 0.6.3 (20)

Transport layout height44→36pt; touch targets stay44pt. Reduced horizontal
transport/panel spacing and side-icon gap; preserved side physical edge12pt and
top16pt clearance. UIchecks cover both landscapes on12/12mini/18ProMax, actual
outer-quarter arrow taps and lower-edge header button taps. All device/case
combinations have passing results after correcting only a subpixel AX assertion
rounding issue.3 geometry cases pass; native core/lighting/audio sources match19.
Archive, signature, dSYM and distribution entitlements verified; Owner Beta-only
upload and Apple readback tracked in Research/Compact20/verification.json.
No new public release or physical phone acceptance is claimed.

20 upload exited0 and Apple processing reached Ready to Test. Beta notes saved,
assigned only Owner Beta (Internal,1tester). Final0.6.3/20 readback shows Testing,
Owner Beta and1invitation. Evidence: Research/Compact20/testflight-testing.png
and verification.json. No physical phone install/acceptance or public release.

## Fixed-size knobs — 0.6.4 (21)

Removed firmware status dot and moved top label/icon artwork4pt upward within
44pt targets; row32pt. The expanded LCD receives recovered height/width while
all8 knobs retain compact-state diameters. Geometry reserves function/knob space
and guards transient invalid reference heights.14 final native unit/render cases
pass; UIvalid-reference checks passed on12/12mini/18ProMax in both landscapes.
Final archive/signature/dSYM/identity/source freeze verified. Owner Beta-only
upload/readback and UI-limit details: Research/Controls21/verification.json.
No firmware/audio/lighting logic changes, public release or phone acceptance.

21 upload succeeded, Apple processing reached Ready to Test, notes saved and
only Owner Beta assigned (Internal,1tester). Final0.6.4/21 readback: Testing,
Owner Beta,1invitation. Evidence: Research/Controls21/testflight-testing.png and
verification.json. No physical phone acceptance or public release implied.

## Anchored controls — 0.6.5 (22)

Left knobs form a rigid centered2×2 group with equal spacing. Right knob/function
group follows the lower panel anchor with compact vertical geometry. Existing
knob diameters/LCD/keyboard/side-corner safety retained. Final-source matrix:15
cases per device on12/12mini/18ProMax,0failures; actual UIcase covers both
landscapes and coordinate taps. Signed archive/dSYM/identity/source freeze verified.
Owner Beta-only upload and Apple status: Research/Anchors22/verification.json.
No new audio/firmware/lighting logic or physical phone acceptance claim.

22 upload exited0; Apple processing reached Ready to Test. Notes saved and
only Owner Beta assigned (Internal,1tester). Final reload confirms0.6.5/22
Testing, Owner Beta and1invitation after a temporary empty status field.
Evidence: Research/Anchors22/testflight-testing.png and verification.json.
Physical phone install/acceptance and public release remain unclaimed.

## Compact right row — 0.6.6 (23)

Right label/knob row is optically centered above the compact function grid and
retains22's lower anchoring in full view.14unit cases plus1UIcase passed on
iPhone12 simulator/both landscapes; geometry covers3phone panel sizes. Signed
archive, source freeze, dSYM and identity verified. Owner Beta-only distribution
and Apple status are recorded in Research/Center23/verification.json.

Apple distribution readback for 0.6.6 (23): upload succeeded, processing completed, What to Test saved, and only the existing Owner Beta internal group (1 tester) assigned. App Store Connect shows Testing with 1 invitation. Proof: `Research/Center23/testflight-testing.png`; receipt: `Research/Center23/verification.json`. Physical iPhone acceptance remains pending; no public App Store release submitted.

0.6.7 (24) distribution completed: Apple upload succeeded, What to Test saved, existing Owner Beta internal group (1 tester) assigned, and App Store Connect verified Testing with 1 invitation. Receipt and screenshot: `Research/Song24/verification.json`, `Research/Song24/testflight-testing.png`. No public release or physical-phone acceptance claimed.

## SLOOP 2.8 — 0.6.8 (25), prepared 2026-10-21

All-eight host workspace87 passed; simulator18 unit/integration/audio tests and
2 real UI scenarios passed. Includes checked predecessor workspace copy and old
project envelope support, original files retained. Official upstream UI/fuzz and
actual2.7.1-to2.8 raw/object migration probes also pass. Signed archive, source
freeze, dSYM, bundle/version and embedded catalog verified.

Upload attempt exited70: Xcode credentials unavailable (missing Xcode-Username)
while Mac is locked. Owner unlock/re-authentication requested. No upload, Apple
processing or group availability is claimed. Receipt: Research/Sloop25/verification.json.
Source-WASM execution tests wait until this TestFlight update is delivered.

0.6.8 (25) upload completed after owner re-added Apple Account in Xcode. Apple
processed build88194d0e-23d4-4e8e-8779-4047d6963a16; What to Test saved; only
Owner Beta (Internal,1tester) assigned. Final iOS Builds readback: Testing,
Owner Beta,1invitation. Screenshot: Research/Sloop25/testflight-testing.png.
API service activation and Developer-key creation were separately owner-approved;
private file retrieval is pending manual Chrome download. API authentication is
not claimed verified. No public release or physical-phone acceptance claimed.

## API-key and local-signing setup completed — 2026-10-21

Private config, API key, certificate request/private key, certificate, profile
and manual internal-only upload options are stored outside this repository at
`~/Library/Application Support/FM1Release/`, with owner-only permissions.
The default uploader now uses those private manual options. The API key keeps
Developer access; local signing avoids its cloud-signing restriction. The
matching Apple Distribution identity is installed in the login keychain and
the FM1-only App Store profile is installed for Xcode. Certificate and profile
expire on 2027-10-21; renewal is an explicit future maintenance step.

Verified live: authenticated app GET returned HTTP200; the existing25archive
exported successfully with explicit API authentication and manual local signing.
The exported IPA passed strict codesign, app/team/version, profile/certificate
matching and release-entitlement checks. A second codesign process succeeded
without another access prompt after the owner authorized the keychain request.
No duplicate build upload was sent. Full upload using the key is therefore
not claimed exercised yet; the next authorized release uses this path.
Receipt: `Research/Sloop25/api-release-setup.json`; redacted export log:
`Research/Sloop25/api-export-manual.log`. API tokens/private key contents were
not printed or committed. The old inaccessible API key is revoked in Apple's
UI; only the replacement remains active.
