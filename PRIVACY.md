# MyDues Privacy Policy

_Last updated: November 24, 2026_

MyDues helps you keep track of your subscriptions and other recurring payments (household bills, taxes and fees, tuition, insurance), their cost and their due dates. It's built so that your information stays with you: on your devices and in your own private iCloud. MyDues has no user accounts, no servers of its own, no analytics and no advertising.

This policy also appears inside the app under **Settings › Privacy**. If the two ever differ, this document is the reference.

## Information MyDues stores

MyDues saves the following in the app's storage on your iPhone or iPad:

- the name you enter during onboarding
- your monthly budget and currency, and your check-in and reminder preferences
- the subscriptions and payments you add (name, plan, price, billing cycle, category, color, payment date, reminder choice and, for ones imported from email, which of your connected addresses it was found in)
- your weekly check-in answers (whether you used each subscription in a given week)

**iCloud sync.** If you're signed in to iCloud, this information is also saved in **your private iCloud database** (CloudKit) and in iCloud key-value storage, so it isn't lost if you delete the app or change device, and it stays in sync on your devices signed in with the same Apple Account. Only you can access your private iCloud data; MyDues's developers can't see it. Apple stores it encrypted, and with Advanced Data Protection turned on it's end-to-end encrypted. You can see and delete it in the Settings app under your name › iCloud. If you're not signed in to iCloud, everything stays on the device.

This information isn't sent to us or to anyone else. Like other app data, it's also included in your device's iCloud or computer backup if you have backups turned on.

## Notifications

Check-in and payment reminders are scheduled with local notifications on your device, so no reminder content leaves your device. iCloud sync uses Apple's silent push notifications only to tell the app that your data changed on another device.

## Import from Email (Gmail, optional)

You can choose to connect one or more Gmail accounts (up to five) so MyDues can find subscriptions and other recurring payments (household bills, taxes and public fees, tuition, insurance) in your receipts, renewals, bills and payment notices. This feature is off until you turn it on, and each account is connected separately.

**What MyDues accesses.** When you connect, you sign in on Google's own page (MyDues never sees your password) and Google asks you to allow one permission: `gmail.readonly`, read-only access to your messages. MyDues uses it to:

- read your Gmail address, to show which accounts are connected;
- search the last 13 months for emails that look like receipts, renewals, plan confirmations, bills, tax or payment notices and tuition emails (up to 500 per account and scan);
- read only the sender and subject of those emails, to skip ads, newsletters, shipping and security notices and older copies of the same receipt;
- download the full content of the remaining emails, up to 150 per account and scan.

MyDues can't send, delete, label or change any email.

**How it's processed.** Emails are downloaded directly from Google to your device over an encrypted connection. They're read by Apple Intelligence using the language model that runs **on your device** (Apple's Foundation Models framework, on-device model only). Email content is:

- never sent to MyDues's developers, to Apple, or to any other third party;
- never used to train or improve any AI model;
- held in memory only while a scan runs, one email at a time, and never saved to storage or logs.

**What's kept.** The scan produces a list of suggested payments (name, price, currency, billing cycle, category, payment date, and the address it was found in). Nothing is added until you review the list and tap Add. Only the payments you choose are saved, in the same way as subscriptions you enter by hand (and synced to your iCloud as described above).

**Your sign-in.** The access and refresh tokens Google issues for each account are stored in your device's Keychain, available only on that device and not synced through iCloud or iCloud Keychain. On a new device you connect your accounts again.

**Disconnecting.** In **Settings › Import from Email**, swipe an account and tap Disconnect: MyDues revokes its access with Google and deletes that account's tokens from your device. You can also remove access at any time from your Google Account at <https://myaccount.google.com/connections>. Subscriptions you already added stay in the app until you delete them.

### Google API Services User Data Policy

MyDues's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Specifically:

- Gmail data is used only to provide the user-facing feature of finding subscriptions and recurring payments in your email;
- Gmail data is not transferred to anyone, except as necessary to provide that feature, to comply with applicable law, or as part of a merger, acquisition or sale of assets with notice to you. In practice, it never leaves your device;
- Gmail data is not used for advertising, including retargeting, personalized or interest-based advertising;
- no human reads your Gmail data. MyDues's developers have no way to access it.

## Apple Intelligence

Email analysis uses only Apple's on-device model and requires a device that supports Apple Intelligence with Apple Intelligence turned on. MyDues doesn't use Private Cloud Compute or any server-based model for this feature.

## Tracking and third parties

MyDues doesn't track you across apps or websites, doesn't include third-party analytics or advertising SDKs, and doesn't sell or share data with data brokers. The external services MyDues contacts are Apple's iCloud (for sync, if you're signed in), Google (only if you connect Gmail) and, if the developers have configured one, the web address that hosts the updated list of service plans and prices.

## Plan suggestions and cheaper alternatives

When you add a subscription by hand, MyDues can suggest the plans of well-known services and their typical prices, and it points out cheaper plans or similar services. This uses a list of plans included in the app. The app may also download an updated copy of that list from a web address chosen by MyDues's developers, at most once a day. That request is a plain download: it contains nothing about you or your subscriptions, and the comparison happens on your device.

**Plans and cancellation pages.** "See Plans and Prices" and "Cancel Subscription" open the service's own pages, and only when you tap them. For well-known services the links are part of the app's list; for Apple's services, your Apple Account subscriptions open. For any other service, your device finds the service's website (from the domain of the email it was imported from, or with a suggestion from Apple Intelligence on the device, always checked by loading the site) and reads its public home and help pages to find the right link; Apple Intelligence picks among the links actually found there. These pages are loaded without cookies or any information about you, and no search engine is used. The page found is remembered with that subscription (and synced through your iCloud). Plans open in an in-app Safari view; cancellation opens in Safari or in your Apple Account, where you're signed in. MyDues doesn't see what you do on those pages.

## Children

MyDues isn't directed at children under 13 and doesn't knowingly collect information from them.

## Deleting your data

- Delete individual subscriptions in the app: the deletion syncs to iCloud and your other devices.
- Disconnect Gmail accounts in Settings to revoke access and delete their sign-in.
- **Settings › Reset MyDues** deletes everything from this device, from your iCloud and from your other devices, and disconnects every Gmail account.
- Deleting the app removes what's on that device; data in your iCloud stays until you reset the app or delete it in the Settings app under your name › iCloud.

Because MyDues doesn't hold your data on any server of its own, there's nothing for us to delete on our side.

## Changes

If this policy changes, the new version will be published here and in the app, with a new "Last updated" date. Material changes to how email is handled will be explained in the app before they take effect.

## Contact

Questions about this policy: _add a support email or website before publishing._
