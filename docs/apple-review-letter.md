# Draft App Review inquiry — not sent

To: Apple Developer Support / App Review
Subject: Guidance requested: offline musical-instrument hardware emulator and firmware catalogue

Hello App Review team,

We are developing an independent iPhone and iPad musical-instrument app that emulates the M-VAVE FM-1 synthesizer. Before submitting it, we would appreciate guidance on the appropriate review treatment of its firmware functionality.

The app has a native touch interface and an interpreter for the synthesizer's CPU and peripherals. It runs synthesizer firmware to generate sound and draw the instrument's display. It does not use JIT compilation or execute firmware as native iOS code. Firmware is interpreted within the emulated device; it is not given access to iOS APIs, contacts, photos, the microphone, or the host filesystem. The host app handles audio output and isolated local save files.

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
