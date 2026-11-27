# MyDues – Google OAuth verification kit

Use these texts in Google Auth Platform → **Centro di verifica** (Verification Center) when you submit.
Everything is in English because Google's review team works in English.

Before pasting, check every sentence is true for the build you submit. Google compares these texts, the privacy policy, the homepage and the video with what the app actually does.

---

## 1. Scope justification (paste into the justification field for `gmail.readonly`)

**Scope:** `https://www.googleapis.com/auth/gmail.readonly`

MyDues is a native iOS app that helps people keep track of their subscriptions, purchases and warranties, and of the dates that matter: the next payment, the return deadline and the warranty expiry. It has an optional feature, Settings > Import from Email, that saves the user from typing these items in by hand.

When the user turns this feature on and grants access, MyDues searches the user's own mailbox for recent receipts, invoices, renewal notices, order confirmations and warranty documents, and reads those messages one at a time. From each message it extracts the details the user would otherwise enter manually: for a subscription, the service name, price, billing frequency and payment date; for an order or warranty, the shop or product, price, purchase date and the return or warranty deadline. The extracted items are shown in a review list. Nothing is saved until the user selects items and taps Add.

**Why gmail.readonly is required.** Every detail the feature needs (price, billing period, renewal date, return deadline, warranty expiry) appears only in the body of the email. The feature cannot work without reading message content. The user cannot be asked to supply this data in another way without losing the purpose of the feature.

**Why narrower scopes are not enough.**
- `gmail.metadata` returns only headers and labels, not the message body, so none of the dates or prices can be read. The feature would not work at all.
- `gmail.labels` and similar scopes expose no message content.
- `gmail.modify`, `gmail.compose`, `gmail.send` and `mail.google.com` give permission to change, send or delete mail. MyDues never does any of these, so they would exceed what the app needs.

`gmail.readonly` is the narrowest scope that allows reading message content. MyDues requests no other Gmail scope and no data for features that are not already in the app.

**How the data is handled.**
- MyDues is a native iOS app. It signs the user in with OAuth 2.0 (authorization code with PKCE) directly with Google. There is no MyDues backend server, and Gmail data is never sent to one.
- Email text is analysed by Apple Intelligence using the model that runs on the user's device (Apple's Foundation Models framework). MyDues does not use Private Cloud Compute or any other server-based model for this.
- Email content is kept in memory only while a scan is running. It is not written to disk, logged, or transmitted anywhere.
- Only the items the user confirms are saved, in the app's own storage on the device and, if the user is signed in to iCloud, in the user's private iCloud (CloudKit) database, which the developers cannot access.
- Access and refresh tokens are stored in the device Keychain, on that device only, and are not synced.
- Gmail data is not used for advertising, is not sold or shared with third parties, and is not read by any person at MyDues.
- The user can disconnect Gmail at any time in the app, which revokes the access, or from their Google Account permissions page.

MyDues's use and transfer to any other app of information received from Google APIs adheres to the Google API Services User Data Policy, including the Limited Use requirements. The same statement appears on the homepage and in the privacy policy.

---

## 2. Short answers for other fields in the form

**App type / how it accesses data:** Native iOS application. OAuth client type "iOS". No server-side component stores or processes Gmail data.

**Does your app store or transmit restricted-scope data on servers you operate?** No. Data flows from Google directly to the user's device. Confirmed items are stored on the device and in the user's own private iCloud.

**Homepage:** https://francescamcoppola.github.io/Duely-ebbast/home.html
**Privacy policy:** https://francescamcoppola.github.io/Duely-ebbast/privacy.html
**Support / contact:** myduesapp@gmail.com

**Demo video:** (paste the YouTube "unlisted" link)

---

## 3. Demo video script (about 2 to 3 minutes)

**Requirements from Google's page** (support.google.com/cloud/answer/13464321):
- Show the full app flow, including the OAuth grant.
- Show the exact app you submitted, with its name and branding (MyDues).
- Show the **complete consent screen**, with the same scopes you request.
- Set the **language selector in the bottom-left corner of the consent screen to English**.
- Show the app features that use each requested scope.

**Set up before recording**
- Record the screen on a real iPhone (Control Center > Screen Recording), with the iPhone language in English.
- Use a **test Gmail account** with sample emails: at least one subscription receipt, one order confirmation and one warranty document. Do not film a real private mailbox.
- Use a build in which Import from Email already finds subscriptions, orders and warranties. Google does not accept features that are not yet implemented.
- Start from a state where Gmail is not connected.
- Add English captions or a voice-over. Keep it calm: nothing needs to be fast.

**Shots, in order**

1. **App and name (10 s).** Home screen with the MyDues icon, open the app. Say or caption: "This is MyDues, an iOS app that tracks subscriptions, purchases and warranties."
2. **Where the feature lives (10 s).** Open Settings > Import from Email. Pause on the explanation text: what is read, that it is analysed on the device, what is kept.
3. **Privacy page (10 s).** Briefly show Settings > Privacy, to show the in-app notice.
4. **Connect Gmail (30 s).** Tap Connect. When Google's page opens, scroll to the bottom-left and show that the language is **English** (change it if needed). Show the app name **MyDues** and the account chooser, then slowly show the **full consent screen** with the permission "View your email messages and settings" ticked. Say: "MyDues asks for one permission: read-only access to Gmail."
5. **Scan (30 s).** Return to the app and tap Scan Emails. Show the progress. Say: "The app reads recent receipts and order emails one at a time. The analysis runs on the device with Apple Intelligence. No email leaves the phone."
6. **Review list (30 s).** Show the found items: at least one subscription (service, price, frequency, date) and one order or warranty (shop or product, price, purchase date, return or warranty deadline). Point out that all fields can be checked and that nothing is saved yet.
7. **Confirm (20 s).** Select items and tap Add. Show them in the main list of the app, with their dates and reminders.
8. **Disconnect (20 s).** Go back to Import from Email and tap Disconnect. Show the screen returning to "not connected". Say: "The user can disconnect at any time, which revokes access."

**Upload:** YouTube, visibility **Unlisted**. Check the link opens in a private window before pasting it in the form.

---

## 4. Before you press Submit

- [ ] The build the reviewers can run (TestFlight or App Store) really finds subscriptions, orders **and** warranties.
- [ ] Branding: name `MyDues`, homepage `.../home.html`, privacy `.../privacy.html`, authorized domain saved.
- [ ] Search Console property verified (done).
- [ ] Data access: only `gmail.readonly`.
- [ ] The privacy policy online contains the Gmail section and the Limited Use sentence (done once pushed).
- [ ] The only OAuth client in the project is the iOS one (delete test clients).
- [ ] Auth Platform > **Pubblico** (Audience): publish the app (status **In produzione**), then Centro di verifica > Submit for verification. After publishing, and until Google verifies the app, users see an "unverified app" warning and the 100-user cap still applies.
- [ ] Reply quickly to Google's emails. They are sent to the contact email set in the project.
