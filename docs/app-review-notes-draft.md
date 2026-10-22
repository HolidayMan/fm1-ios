# Draft Review Notes — native instrument edition

Not sent. Fill final product/developer identity, policy/support URLs, exact engine
list and asset-distribution permissions after inspecting the submission archive.
Do not submit this text if the research/WASM backends remain reachable or shipped.

This independent musical instrument app uses a native iOS touch interface. The
supported instrument application and DSP sources are compiled ahead of time into
the signed app. Users choose from the fixed reviewed instrument collection; they
cannot import arbitrary firmware, change CPU execution modes, install executable
plugins or compile new host code.

[Describe the exact resource path in the final artifact: bundled starter data or
explicit, size-disclosed downloads of exact pinned packages. Package containers
may contain original firmware instruction bytes; explain which fields the native
engines read and show that downloaded instructions are never executed. Do not
call complete firmware packages merely preset files. Supply source/package pins
and a code/data boundary explanation for Review if downloads remain.]

The app needs no synthesizer hardware, account, microphone, contacts or photo
permissions. Projects and preferences stay in the app container and are retained
when changing the selected instrument. Device/iCloud backups follow system settings.
There are no ads or analytics SDKs. [Verify this against the final privacy report.]

To test: launch the app, select [bundled starter instrument] from the top-left
instrument button if needed, play the lower and upper key rows, drag knobs
vertically, and use the instrument's own PLAY/STOP and SAVE controls. The top
transport pauses/resumes app audio; its right-side chevron collapses/restores the
transport. Tap the instrument LCD to enlarge it. Appearance selection changes the
panel finish without changing instrument audio. [Confirm instructions per included
engine and verify first-run/offline behavior before upload.]

FM1 Open is a portable source preview and may sound different from the hardware.
The app does not imply endorsement by or affiliation with M-VAVE. Third-party
license notices and source references are available in About. [Confirm compatible
distribution rights and independent product branding before making this statement.]
