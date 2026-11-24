# MyDues
An iOS app to keep track of subscriptions and recurring payments: bills, taxes, tuition and insurance.

## Privacy

See [PRIVACY.md](PRIVACY.md). The same notice is in the app under **Settings › Privacy**
(`Views/Settings/PrivacyView.swift`); keep the two, and the App Store privacy label, in sync.

## Import from Email (Gmail + Apple Intelligence)

Settings › Import from Email lets users connect up to five Gmail accounts. The app searches recent
billing emails in each (receipts, renewals, household bills, tax and pagoPA notices, tuition,
insurance), reads them with Apple Intelligence **on the device** (`SystemLanguageModel`, Foundation
Models), and suggests payments that the user confirms before anything is added.

- No backend and no third-party SDK: OAuth 2.0 with PKCE via `WebAuthenticationSession`,
  Gmail REST API via `URLSession`.
- Scope: `https://www.googleapis.com/auth/gmail.readonly` only.
- Tokens for every account are stored in one Keychain item (`AfterFirstUnlockThisDeviceOnly`,
  never synced). The single-account item of earlier versions is migrated automatically. Email
  content is never written to disk.

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

## iCloud sync

Subscriptions and check-ins are stored with SwiftData mirrored to the user's **private CloudKit
database** (`Services/Cloud/Persistence.swift`); preferences (name, budget, currency, check-in,
onboarding done) are mirrored to iCloud key-value storage (`CloudSettingsSync.swift`). Data
survives a reinstall and syncs between devices. Without iCloud the store keeps working locally.

Setup in Xcode (needed once per developer team):

1. Target › Signing & Capabilities: the project already points to `MyDues.entitlements` with
   **iCloud** (CloudKit + key-value storage) and **Push Notifications**, and `Info.plist` enables
   **Background Modes › Remote notifications**. Select your team so Xcode registers them.
2. In the iCloud capability, add the container. Do this **only from a Mac signed in with the
   team that owns the bundle ID**: container identifiers are global and can never be deleted, so
   one registered by another team is lost for good. The app uses the first container listed in
   the entitlements (`cloudKitDatabase: .automatic`), so no code change is needed.
3. Before shipping, open the CloudKit Console and **deploy the schema to Production**
   (development builds create it automatically on first sync). Every new model property must
   have a default value or be optional.
4. For a release build set `aps-environment` to `production` (Xcode does this when archiving
   with automatic signing).

## Plans and cheaper alternatives

`Resources/PlanCatalog.json` lists popular services, their plans and typical prices (EUR, Italy,
updated November 2026). It powers plan suggestions in the editor (pick "Netflix › Premium" and
price and cycle are filled in) and the "Ways to Save" card / section (cheaper plans of the same
service, or the cheapest plan of a similar service in the same `groups`).

There's no free public API with subscription prices, so the catalog is a JSON file. To update
prices without a release, publish the file at a public URL (a public GitHub repository's raw URL
or a Gist) and set `PlanCatalogConfiguration.remoteURL`: the app downloads it at most once a day
and keeps it when its `updated` date is newer than the bundled copy. Prices are per currency
(`"prices": {"EUR": "13.99", "USD": "17.99"}`); plans without the user's currency are shown
without a price. Plans with `eligibility` (e.g. students) are never suggested as alternatives.
