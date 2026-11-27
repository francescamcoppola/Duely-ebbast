//
//  EmailText.swift
//  MyDues
//
//  Turns email bodies into short, clean text for the on-device model: decodes Gmail's
//  base64url, strips HTML, drops links and noise, and caps the length so one email always
//  fits in the model's context. Pure string work, no I/O.
//

import Foundation

nonisolated enum EmailText {
    /// Gmail's base64url as bytes (attachments).
    static func base64URLData(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    static func base64URLDecoded(_ string: String) -> String? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func plainText(fromHTML html: String) -> String {
        var text = html
        // Content that's never visible text.
        for pattern in ["(?is)<head\\b.*?</head>", "(?is)<style\\b.*?</style>", "(?is)<script\\b.*?</script>", "(?s)<!--.*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Block-level ends become line breaks, so "Total" and "€9.99" in table cells stay apart.
        text = text.replacingOccurrences(
            of: "(?i)<br\\s*/?>|</(p|div|tr|li|h[1-6]|table)>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "(?i)</t[dh]>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(text)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&#39;": "'", "&euro;": "€", "&pound;": "£", "&yen;": "¥", "&cent;": "¢", "&copy;": "©",
            "&reg;": "®", "&trade;": "™", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&zwnj;": "", "&shy;": "",
        ]
        var result = text
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }

        // Numeric entities: &#8364; and &#x20AC;
        let pattern = /&#(x[0-9a-fA-F]+|[0-9]+);/
        result = result.replacing(pattern) { match in
            let token = match.output.1
            let value = token.hasPrefix("x") || token.hasPrefix("X")
                ? UInt32(token.dropFirst(), radix: 16)
                : UInt32(token)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
        }
        return result
    }

    /// Collapses whitespace, removes links and invisible characters, and trims to `limit` characters.
    static func normalized(_ text: String, limit: Int = 4000) -> String {
        var text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            // Zero-width characters some senders use as preheader padding.
            .replacingOccurrences(of: "[\\u200B-\\u200D\\u2060\\uFEFF\\u034F\\u00AD]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\u00A0", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        text = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return truncated(text, limit: limit)
    }

    static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
