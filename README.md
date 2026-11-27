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

A scan has three steps per account (`EmailImportModel.scanAccount`): Gmail search of the last 13
months (up to 500 IDs), a header-only pass (`format=metadata`: sender, subject, List-Unsubscribe)
where `BillingEmailFilter` skips ads, newsletters, shipping and security notices and keeps only the
newest two emails per sender+subject, then full download and on-device reading of what's left
(up to 150).

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
   (`MyDues/Services/Gmail/GmailConfiguration.swift`). Until it's set, the feature shows as
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

## Widgets and Screen Time (app extensions)

The project has three targets: the app (`MyDues`), `MyDuesWidgets` (Home Screen and Lock
Screen widgets) and `UsageMonitor` (Screen Time / DeviceActivity monitor). Code shared by all three
is in `MyDuesShared/` and talks through the App Group `group.com.francescamariacoppola.Duely`.

- **Widgets** read `WidgetSnapshot`, written by the app (`Services/Extensions/WidgetSync.swift`)
  whenever subscriptions, budget, currency or language change. Texts come translated from the
  app, so widgets follow the in-app language.
- **Screen Time**: in a subscription's detail, "Track Usage with Screen Time" asks for permission
  and opens Apple's app picker. A daily DeviceActivity schedule records the days each linked app
  is used for 5+ minutes (`UsageLinks`). Check-ins are pre-filled from it (and answered
  automatically when every subscription is linked); the monitor sends a reminder when a paid app
  hasn't been opened for a week. The app never learns which app was picked or what was done in it.

Setup (once, on the Mac of the team that owns the bundle ID):

1. Open the project, select each target › Signing & Capabilities and let Xcode register the App
   IDs `….Duely.Widgets` and `….Duely.UsageMonitor` and the App Group
   `group.com.francescamariacoppola.Duely` (tick it in the App Groups capability of all three).
2. **Family Controls (Screen Time)**: Apple allows it in development builds only. It's in
   `MyDues-Debug.entitlements` and `UsageMonitor-Debug.entitlements` (Debug configuration), so
   TestFlight/App Store builds still sign and simply show Screen Time as unavailable. To ship it,
   request the distribution entitlement at
   https://developer.apple.com/contact/request/family-controls-distribution, then add
   `com.apple.developer.family-controls` to `MyDues.entitlements` and `UsageMonitor.entitlements`.
3. Screen Time doesn't work in the Simulator: test it on an iPhone.

## Language

The first onboarding screen picks the language (preset to the device's); Settings › Language
changes it later. Switching rebuilds the whole interface in the new language right away
(`Services/AppLanguage.swift`): iOS doesn't let apps relaunch themselves. Inglisc (`it-VA`) is
generated from the Italian strings: every word's final vowels become "s".
