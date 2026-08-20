//
//  HTMLDocument.swift
//  Wishlist
//
//  A deliberately small HTML reader. Wishlist only needs three things from a
//  product page — the meta tags, the title and any embedded JSON-LD — so it
//  scans for exactly those rather than pulling in a full DOM parser.
//

import Foundation

nonisolated struct HTMLDocument: Sendable {
    /// Meta tag values keyed by their lowercased `property`, `name` or
    /// `itemprop` attribute.
    var metaTags: [String: String]
    var title: String?
    var canonicalURL: String?
    /// Raw contents of every `<script type="application/ld+json">` block.
    var jsonLDBlocks: [String]

    func meta(_ keys: [String]) -> String? {
        for key in keys {
            if let value = metaTags[key], !value.isEmpty { return value }
        }
        return nil
    }
}

nonisolated enum HTMLParser {
    /// Pages beyond this size are truncated: everything Wishlist reads lives in
    /// the head, and parsing megabytes of markup on a phone is not free.
    private static let scanLimit = 600_000

    static func parse(_ data: Data, contentTypeHeader: String?) -> HTMLDocument {
        parse(decode(data, contentTypeHeader: contentTypeHeader))
    }

    static func parse(_ rawHTML: String) -> HTMLDocument {
        let html = rawHTML.count > scanLimit
            ? String(rawHTML.prefix(scanLimit))
            : rawHTML

        return HTMLDocument(
            metaTags: metaTags(in: html),
            title: title(in: html),
            canonicalURL: canonicalURL(in: html),
            jsonLDBlocks: jsonLDBlocks(in: html)
        )
    }

    // MARK: - Text decoding

    /// HTML is still served in a surprising number of encodings. Try the one
    /// the server declared, then UTF-8, then the Latin-1 family.
    static func decode(_ data: Data, contentTypeHeader: String?) -> String {
        if let charset = charset(fromContentType: contentTypeHeader),
           let encoding = stringEncoding(forCharset: charset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        if let windows = String(data: data, encoding: .windowsCP1252) { return windows }
        return String(decoding: data, as: UTF8.self)
    }

    private static func charset(fromContentType header: String?) -> String? {
        guard let header, let range = header.range(of: "charset=", options: .caseInsensitive) else {
            return nil
        }
        let value = header[range.upperBound...]
            .prefix { $0 != ";" && $0 != " " }
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return value.isEmpty ? nil : value.lowercased()
    }

    private static func stringEncoding(forCharset charset: String) -> String.Encoding? {
        switch charset {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1", "iso8859-1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16": return .utf16
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        default: return nil
        }
    }

    // MARK: - Tag scanning

    private static func metaTags(in html: String) -> [String: String] {
        var results: [String: String] = [:]
        var cursor = html.startIndex

        while let open = html.range(of: "<meta", options: .caseInsensitive, range: cursor..<html.endIndex) {
            guard let close = html.range(of: ">", range: open.upperBound..<html.endIndex) else { break }
            let attributes = parseAttributes(in: html[open.upperBound..<close.lowerBound])
            cursor = close.upperBound

            guard let content = attributes["content"], !content.isEmpty else { continue }
            for keyAttribute in ["property", "name", "itemprop"] {
                if let key = attributes[keyAttribute]?.lowercased(), !key.isEmpty {
                    // First declaration wins: pages often repeat og: tags.
                    if results[key] == nil { results[key] = content }
                }
            }
        }
        return results
    }

    private static func title(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let contentStart = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title", options: .caseInsensitive, range: contentStart.upperBound..<html.endIndex)
        else { return nil }
        let raw = String(html[contentStart.upperBound..<close.lowerBound])
        let decoded = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func canonicalURL(in html: String) -> String? {
        var cursor = html.startIndex
        while let open = html.range(of: "<link", options: .caseInsensitive, range: cursor..<html.endIndex) {
            guard let close = html.range(of: ">", range: open.upperBound..<html.endIndex) else { break }
            let attributes = parseAttributes(in: html[open.upperBound..<close.lowerBound])
            cursor = close.upperBound
            if attributes["rel"]?.lowercased() == "canonical", let href = attributes["href"] {
                return href
            }
        }
        return nil
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var cursor = html.startIndex

        while let open = html.range(of: "<script", options: .caseInsensitive, range: cursor..<html.endIndex) {
            guard let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex) else { break }
            let attributes = parseAttributes(in: html[open.upperBound..<tagEnd.lowerBound])
            guard let close = html.range(of: "</script", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex) else {
                break
            }
            cursor = close.upperBound

            if attributes["type"]?.lowercased().contains("ld+json") == true {
                let body = String(html[tagEnd.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { blocks.append(body) }
            }
            // Only the first handful of blocks are worth keeping.
            if blocks.count >= 12 { break }
        }
        return blocks
    }

    /// Reads `key="value"`, `key='value'` and bare `key=value` pairs out of the
    /// inside of a tag.
    private static func parseAttributes(in fragment: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = fragment.startIndex

        while index < fragment.endIndex {
            // Skip to the start of a name.
            while index < fragment.endIndex, !fragment[index].isLetter, fragment[index] != "_" {
                index = fragment.index(after: index)
            }
            guard index < fragment.endIndex else { break }

            let nameStart = index
            while index < fragment.endIndex,
                  fragment[index].isLetter || fragment[index].isNumber
                    || fragment[index] == "-" || fragment[index] == "_" || fragment[index] == ":" {
                index = fragment.index(after: index)
            }
            let name = String(fragment[nameStart..<index]).lowercased()

            // Skip whitespace before "=".
            while index < fragment.endIndex, fragment[index] == " " {
                index = fragment.index(after: index)
            }
            guard index < fragment.endIndex, fragment[index] == "=" else {
                if !name.isEmpty { attributes[name] = "" }
                continue
            }
            index = fragment.index(after: index)
            while index < fragment.endIndex, fragment[index] == " " {
                index = fragment.index(after: index)
            }
            guard index < fragment.endIndex else { break }

            var value = ""
            let quote = fragment[index]
            if quote == "\"" || quote == "'" {
                index = fragment.index(after: index)
                let valueStart = index
                while index < fragment.endIndex, fragment[index] != quote {
                    index = fragment.index(after: index)
                }
                value = String(fragment[valueStart..<index])
                if index < fragment.endIndex { index = fragment.index(after: index) }
            } else {
                let valueStart = index
                while index < fragment.endIndex, fragment[index] != " " {
                    index = fragment.index(after: index)
                }
                value = String(fragment[valueStart..<index])
            }

            if !name.isEmpty {
                attributes[name] = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return attributes
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "pound": "£", "euro": "€", "yen": "¥", "cent": "¢",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—",
        "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "deg": "°", "times": "×", "middot": "·", "bull": "•", "dollar": "$"
    ]

    /// Resolves the entity forms that actually appear in product titles.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let searchEnd = text.index(index, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text.range(of: ";", range: index..<searchEnd) else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semicolon.lowerBound])
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let scalarValue: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") {
                    scalarValue = UInt32(digits.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(digits)
                }
                if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                    result.append(Character(scalar))
                } else {
                    result.append(contentsOf: text[index..<semicolon.upperBound])
                }
            } else if let replacement = namedEntities[body.lowercased()] {
                result.append(replacement)
            } else {
                result.append(contentsOf: text[index..<semicolon.upperBound])
            }
            index = semicolon.upperBound
        }
        return result
    }

    /// Strips tags from a snippet of HTML so a product description reads as
    /// plain text.
    static func plainText(from html: String) -> String {
        var result = ""
        var insideTag = false
        for character in html {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; result.append(" "); continue }
            if !insideTag { result.append(character) }
        }
        return decodeEntities(result)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
