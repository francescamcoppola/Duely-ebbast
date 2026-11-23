# MyiOSApp
New repo for an iOS App

## Privacy

See [PRIVACY.md](PRIVACY.md). The same notice is in the app under **Settings › Privacy**
(`Views/Settings/PrivacyView.swift`); keep the two, and the App Store privacy label, in sync.

## Import from Email (Gmail + Apple Intelligence)

Settings › Import from Email lets users connect Gmail. The app searches recent billing emails,
reads them with Apple Intelligence **on the device** (`SystemLanguageModel`, Foundation Models),
and suggests subscriptions that the user confirms before anything is added.

- No backend and no third-party SDK: OAuth 2.0 with PKCE via `WebAuthenticationSession`,
  Gmail REST API via `URLSession`.
- Scope: `https://www.googleapis.com/auth/gmail.readonly` only.
- Tokens are stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`). Email content is never
  written to disk.

Code: `Services/Gmail/` (auth, API, text cleanup), `Services/EmailImport/` (on-device extraction,
candidate merging, scan flow), `Views/Settings/EmailImportView.swift` and `ImportReviewView.swift`.

### Setup

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project and enable the
   **Gmail API**.
2. Configure the **OAuth consent screen**: app name, support email, privacy policy URL (publish
   `PRIVACY.md`), and add the `gmail.readonly` scope. While the app is in *Testing*, add the
   Google accounts that may sign in as test users.
3. Create an **OAuth client ID** of type **iOS** with bundle ID `com.diegotamez.DuelyProject`.
4. Paste the client ID into `GmailConfiguration.clientID`
   (`DuelyProject/Services/Gmail/GmailConfiguration.swift`). Until it's set, the feature shows as
   unavailable. No URL scheme needs to be added to Info.plist: `WebAuthenticationSession` catches
   the redirect.

`gmail.readonly` is a *restricted* Gmail scope. Before releasing to the public, Google requires
app verification and may require a third-party security assessment; check Google's current
requirements for restricted scopes.

### Requirements

Scanning needs a device with Apple Intelligence turned on. The simulator only runs the model when
the Mac running it supports Apple Intelligence. Connecting Gmail works everywhere.
