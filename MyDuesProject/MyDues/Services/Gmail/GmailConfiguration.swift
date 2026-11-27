//
//  GmailConfiguration.swift
//  MyDues
//
//  OAuth settings for the optional Gmail import. The app talks to Google directly: no backend,
//  no third-party SDK. See README.md for how to create the client ID.
//

import Foundation

nonisolated enum GmailConfiguration {
    /// iOS OAuth client ID from Google Cloud Console (APIs & Services → Credentials → iOS).
    /// Looks like "1234567890-abc123.apps.googleusercontent.com". Public by design: iOS
    /// clients have no secret, PKCE protects the sign-in instead.
    /// While empty, the Gmail import is shown as unavailable.
    static let clientID = "376329629619-fje1ndspl86mod67kb4qupv2q7fvptb4.apps.googleusercontent.com"

    static var isConfigured: Bool {
        FeatureFlags.emailImport && clientID.hasSuffix(".apps.googleusercontent.com")
    }

    /// Read-only access to messages. The app never sends, deletes, labels or modifies email.
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    /// Google's redirect scheme for iOS clients: the client ID reversed
    /// ("com.googleusercontent.apps.1234567890-abc123").
    static var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let apiBase = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!
}
