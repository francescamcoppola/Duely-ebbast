//
//  GmailAuth.swift
//  DuelyProject
//
//  OAuth 2.0 for installed apps (authorization code + PKCE), as Google documents for iOS clients.
//  The browser step is run by the caller with `WebAuthenticationSession`; this file builds the
//  request, validates the callback and talks to Google's token endpoint. Tokens live only in
//  the Keychain.
//

import Foundation
import CryptoKit
import Security

nonisolated struct GmailTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    /// The connected address, shown in Settings.
    var email: String?

    /// Refreshes a minute early so a request never starts with a token about to expire.
    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

nonisolated enum GmailAuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidCallback
    case accessDenied
    case scopeNotGranted
    case signedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "Gmail import isn't set up in this version of the app.")
        case .invalidCallback:
            String(localized: "Google didn't complete the sign-in. Try again.")
        case .accessDenied:
            String(localized: "Access to Gmail wasn't allowed.")
        case .scopeNotGranted:
            String(localized: "Allow “View your email messages and settings” on Google's screen so emails can be scanned.")
        case .signedOut:
            String(localized: "Your Gmail connection expired. Connect again to continue.")
        case .server:
            String(localized: "Couldn't reach Google. Check your connection and try again.")
        }
    }
}

/// A sign-in in progress: the URL to open, plus the secrets needed to finish it.
nonisolated struct GmailAuthorizationRequest: Sendable {
    let url: URL
    let state: String
    let codeVerifier: String
}

nonisolated enum GmailAuth {
    private static let keychainAccount = "tokens"

    // MARK: Stored tokens

    static func storedTokens() -> GmailTokens? {
        guard let data = KeychainStore.data(for: keychainAccount) else { return nil }
        return try? JSONDecoder().decode(GmailTokens.self, from: data)
    }

    static func store(_ tokens: GmailTokens) throws {
        try KeychainStore.set(JSONEncoder().encode(tokens), for: keychainAccount)
    }

    static func deleteStoredTokens() {
        KeychainStore.delete(keychainAccount)
    }

    // MARK: Authorization

    static func makeAuthorizationRequest() throws -> GmailAuthorizationRequest {
        guard GmailConfiguration.isConfigured else { throw GmailAuthError.notConfigured }
        let verifier = randomURLSafeString(byteCount: 32)
        let state = randomURLSafeString(byteCount: 16)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(url: GmailConfiguration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GmailConfiguration.clientID),
            URLQueryItem(name: "redirect_uri", value: GmailConfiguration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailConfiguration.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return GmailAuthorizationRequest(url: components.url!, state: state, codeVerifier: verifier)
    }

    /// Reads the authorization code from Google's redirect, rejecting anything that doesn't match.
    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == expectedState else { throw GmailAuthError.invalidCallback }
        if value("error") != nil { throw GmailAuthError.accessDenied }
        guard let code = value("code"), !code.isEmpty else { throw GmailAuthError.invalidCallback }
        return code
    }

    static func exchange(code: String, codeVerifier: String) async throws -> GmailTokens {
        let response: TokenResponse
        do {
            response = try await tokenRequest([
                "client_id": GmailConfiguration.clientID,
                "code": code,
                "code_verifier": codeVerifier,
                "grant_type": "authorization_code",
                "redirect_uri": GmailConfiguration.redirectURI,
            ])
        } catch GmailAuthError.signedOut {
            // A rejected code means the sign-in didn't complete, not that a session expired.
            throw GmailAuthError.invalidCallback
        }
        // Google lets people untick individual permissions on the consent screen.
        guard response.scope?.split(separator: " ").contains(Substring(GmailConfiguration.scope)) ?? false else {
            if let refresh = response.refresh_token { await revoke(token: refresh) }
            throw GmailAuthError.scopeNotGranted
        }
        return GmailTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in ?? 3600))
        )
    }

    static func refreshed(_ tokens: GmailTokens) async throws -> GmailTokens {
        guard let refreshToken = tokens.refreshToken else { throw GmailAuthError.signedOut }
        let response = try await tokenRequest([
            "client_id": GmailConfiguration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        var updated = tokens
        updated.accessToken = response.access_token
        updated.expiresAt = .now.addingTimeInterval(TimeInterval(response.expires_in ?? 3600))
        return updated
    }

    /// Ends the app's access on Google's side too, so it disappears from the user's Google
    /// Account → Security → Third-party connections. Best effort: local tokens are deleted anyway.
    static func revoke(token: String) async {
        var request = URLRequest(url: GmailConfiguration.revokeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Helpers

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
        let scope: String?
    }

    private static func tokenRequest(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: GmailConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 {
            // invalid_grant: the refresh token was revoked or expired.
            throw GmailAuthError.signedOut
        }
        guard (200..<300).contains(status) else { throw GmailAuthError.server("HTTP \(status)") }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
