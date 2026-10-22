# App Store preparation — native instruments

Work in progress, checked against Apple's published guidance on 18 October 2026.
Previous builds have been distributed through owner-only internal TestFlight.
No public App Store submission/approval or distribution-rights clearance is implied. This document describes concrete changes and remaining release gates;
it is not a claim that the current development binary is submission-ready.

## Product scope

The consumer interface presents a curated collection of compiled instruments.
The native/WASM selector, CPU-frequency controls, arbitrary package import and
experimental runtime statistics are removed from this interface. Unsupported
previous packages and saves are preserved on disk, rather than erased. Native-only
loading checks exact package bytes against the linked registry, rejects unsupported
imports/loads and ignores obsolete experimental execution preferences. The research
engine APIs remain available in Debug for local regression tools. Release now
compiles out research handlers and interpreter dependencies, excludes WebEngine
resources and audits the built bundle; see [native store boundary](native-store-build.md).
Signed distribution archive validation remains a separate submission check.

The current curated selection is SLOOP 2.8, Felucca 1.6.1, X0X 1.1.0,
Melodee 1.4.5, FM1 Open V14 portable preview, Skiff 1.4, FoMni 0.4 and
Jangada 1.0.1. This is the local preparation build's selection, not a cleared
store-distribution list.

Instrument source and DSP must be compiled into the signed application. Listing
or downloading a package is not evidence that its engine was compiled, that its
sound matches hardware, or that its resources may legally be distributed.
The FM1 Open portable preview must remain clearly labelled as potentially sounding
different from the hardware. Firmware popularity is a dated GitHub-interest proxy,
not an install/download ranking.

## Concrete interface pass

- Center the upper keyboard keys halfway between the corresponding lower keys.
- Keep the native transport, consistent dismiss buttons, labelled icon buttons,
  search, download progress/cancellation and accessible error alerts.
- Use device-neutral library wording and disclose the resource download size
  before the user starts the first download (Review 4.2.3(ii)).
- Retain all required license/source attribution in About.
- Provide readable in-app privacy information; a published privacy-policy URL
  is now configured in the app; App Store Connect must match it before submission.
- Refine the regular-height iPad panel spacing before final visual acceptance;
  passing geometry tests alone does not settle tablet polish.
- Validate landscape left/right, compact phone, iPad, safe-area controls, keyboard
  touch gutters, playback interruption/recovery and saved-work migration.
- Perform physical VoiceOver, larger text, increased contrast, reduced motion,
  Switch Control and haptic/audio-route checks. Custom firmware-rendered LCD text
  does not automatically become accessible because the surrounding app is native.

## Required release gates still open

1. **Distribution rights.** Existing SLOOP/family host adapters and firmware use
   GPL-3.0 components. Review applicable App Store distribution terms and obtain
   a compatible license/permission where necessary; retaining notices alone does
   not settle this. Check every sample, font and factory sound bank separately.
   Melodee's Casio/Sequential factory-program redistribution permission is not
   established by the current upstream source notices. Jangada's generator uses
   the Hügelton Sample Pack while its licensing notice reserves those assets;
   distribution permission is unresolved. Skiff's generated loop provenance and
   upstream notices are retained; this does not establish all third-party rights.
   New sources require their own pinned provenance and resource review.
2. **Branding.** Confirm rights to use M-VAVE/FM-1 product identity/artwork, or
   choose independent product branding. The app must not imply affiliation.
3. **Artifact boundary.** Produce a native-only signed archive with no reachable
   research/WASM/import paths or undocumented experimental functionality; inspect
   resources and executable dependencies, then run archive validation with proper
   App Store distribution signing. Release now enforces the compiled boundary and
   automatic bundle audit; this does not replace signed archive validation. This is
   stronger than hiding a button (Review 2.5.2 and 2.5.19).
4. **Self-contained launch.** Prefer licensed bundled starter content. If initial
   resources remain downloads, show size/consent and handle offline, IPv6-only,
   cancellation, corrupt/missing assets and unavailable upstream hosting.
5. **Privacy/support.** Publish policy/support URLs under the developer's control,
   fill legal publisher/contact details, verify App Privacy answers, audit final
   dependencies/API symbols and regenerate the archive privacy report. The draft
   manifest declares private app UserDefaults and monotonic elapsed-event timing;
   it is not a replacement for the final binary audit.
6. **Device acceptance.** Test every included engine with audio, controls, complete
   save/reopen, isolation and sustained realistic maximum load on the oldest
   supported physical device. Simulator results are separate evidence.
7. **Completeness.** Decide whether the portable FM1 Open preview is a complete,
   supported feature for the store product; otherwise omit it from the submission
   rather than publishing an unfinished/beta feature. Avoid claims of original
   factory sounds, hardware parity or unimplemented USB/MIDI functionality.
8. **Metadata.** Final name, age rating, screenshots, description, version,
   supported devices/orientations, price and Review Notes must match the exact
   uploaded artifact. Explain the compiled-source engines and downloadable
   resource boundaries truthfully. Do not describe arbitrary firmware execution
   as just preset data.

## Primary references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  2.1 completeness, 2.5.2 executable functionality, 2.5.19 documented features,
  4.2.3 initial resources, 5.1.1 privacy and 5.2 intellectual property.
- [Human Interface Guidelines: accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Human Interface Guidelines: layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Human Interface Guidelines: buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [App privacy metadata](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
