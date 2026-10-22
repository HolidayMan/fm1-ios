# Privacy policy — draft, not published

Before release, insert the independent app name, legal publisher, effective date,
support contact and permanent public policy URL. Reconcile this draft with the
exact shipped build and actual network providers.

The app lets you play musical instruments on your device. It does not require
an account or microphone access, and contains no advertising or analytics SDK.
We do not collect recordings, projects, usage histories, identifiers or contact
information through an app-operated service.

Instrument projects, downloaded resources and preferences are stored in the app's
local container. System device/iCloud backups may include these files according
to your Apple backup settings. Removing the app removes its local data; retained
system backups are managed through Apple's settings. No account deletion flow is
needed because the app does not create accounts.

When you explicitly download an instrument resource or open a source/license link,
your device connects to the listed third-party host (for example GitHub). That
host receives ordinary network request information such as your IP address under
its own privacy policy. Downloading does not upload your musical projects. We do
not operate a tracking endpoint or sell personal information.

The app stores appearance, selected instrument and playback-related preferences
privately using UserDefaults. It uses monotonic timing to schedule sound, haptics
and UI events and measure intervals; no device boot-time value is transmitted.
Local development diagnostics must be reviewed or disabled for the final store
build. This policy must remain accessible from inside the app and its store page.
