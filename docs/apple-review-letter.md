> Historical universal-firmware inquiry. The current native-only preparation is
> described in [app-store-preparation.md](app-store-preparation.md) and
> [app-review-notes-draft.md](app-review-notes-draft.md). This letter was not sent
> and does not describe the current consumer interface.

# Draft App Review inquiry — not sent

To: Apple Developer Support / App Review
Subject: Guidance requested: offline musical-instrument hardware emulator and firmware catalogue

Hello App Review team,

We are developing an independent iPhone and iPad musical-instrument app that emulates the M-VAVE FM-1 synthesizer. Before submitting it, we would appreciate guidance on the appropriate review treatment of its firmware functionality.

The app has a native touch interface and a hybrid audio engine. For a specifically supported SLOOP release, its firmware source is compiled into the signed app and runs through a host adapter. Other packages execute through an interpreter for the synthesizer's CPU and peripherals. Both routes generate sound and draw the instrument's display. It does not use runtime JIT compilation or load downloaded packages as native iOS executables. For performance, the signed app may include emulator routines specialized at build time for exact known instruction blocks; other blocks use the general interpreter. Downloading a package cannot generate or modify executable host code. The native firmware adapter exposes a limited instrument hardware/storage interface; downloaded firmware has only the emulated device interface. Neither route exposes contacts, photos, the microphone or general host filesystem access to a downloaded package. The host app handles audio output and isolated local save files.

Our intended workflow lets a user select a firmware release from an in-app catalogue or import an FM-1 .fwsc package from Files. Catalogue downloads are versioned and checked against a SHA-256 digest before package validation. These packages can substantially change the musical instrument's engines, sequencer and on-screen interface. We therefore want to disclose this functionality explicitly rather than characterize the packages only as presets or sound assets.

Could you advise whether this musical-instrument emulator and firmware workflow is eligible under the applicable App Review Guidelines, including 2.5.2 and 4.7, and what restrictions or review materials would apply? We recognize that the published emulator provisions may not necessarily cover musical hardware in the same way as game consoles.

We can provide a demonstration video, a review build, exact example firmware releases, source and licensing information, and an explanation of the interpreter and its host-access boundaries. Before submission we will verify the distribution rights and required notices for each included or linked release, finalize the supported catalogue, and document compatibility and performance on supported devices.

If downloadable firmware is not eligible in this form, please clarify whether a catalogue limited to firmware included in the reviewed app binary would be an acceptable route and what review requirements would apply.

Thank you,
[Developer name / organization]
[Apple Developer Team ID]
[App name and App Store Connect record, when created]
[Contact email]

---

Preparation notes: fill the placeholders only when preparing the actual submission; re-check the then-current guidelines and implemented features. This draft is a request for guidance, not a claim of prior approval or a completed security audit.

References:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/contact/app-store/
