//
//  RetailerIdentifier.swift
//  Wishlist
//
//  Step two of the pipeline: work out which store a link belongs to. A short
//  table covers the stores people actually paste; everything else is derived
//  from the domain, which is always better than showing "Unknown".
//

import Foundation

nonisolated enum RetailerIdentifier {
    /// Second-level domain (without suffix) to display name.
    private static let knownRetailers: [String: String] = [
        "amazon": "Amazon",
        "ebay": "eBay",
        "etsy": "Etsy",
        "johnlewis": "John Lewis",
        "argos": "Argos",
        "currys": "Currys",
        "very": "Very",
        "asos": "ASOS",
        "next": "Next",
        "marksandspencer": "M&S",
        "selfridges": "Selfridges",
        "harrods": "Harrods",
        "screwfix": "Screwfix",
        "wayfair": "Wayfair",
        "ikea": "IKEA",
        "apple": "Apple",
        "bestbuy": "Best Buy",
        "target": "Target",
        "walmart": "Walmart",
        "costco": "Costco",
        "newegg": "Newegg",
        "bhphotovideo": "B&H",
        "adorama": "Adorama",
        "nike": "Nike",
        "adidas": "Adidas",
        "zara": "Zara",
        "uniqlo": "Uniqlo",
        "hm": "H&M",
        "zalando": "Zalando",
        "aliexpress": "AliExpress",
        "temu": "Temu",
        "shein": "SHEIN",
        "backmarket": "Back Market",
        "decathlon": "Decathlon",
        "sportsdirect": "Sports Direct",
        "waterstones": "Waterstones",
        "boots": "Boots",
        "superdrug": "Superdrug",
        "sephora": "Sephora",
        "lego": "LEGO",
        "gamestop": "GameStop",
        "steampowered": "Steam",
        "nintendo": "Nintendo",
        "playstation": "PlayStation",
        "dyson": "Dyson",
        "sonos": "Sonos",
        "bose": "Bose",
        "samsung": "Samsung",
        "dell": "Dell",
        "lenovo": "Lenovo",
        "hp": "HP",
        "wex": "Wex Photo Video",
        "richersounds": "Richer Sounds",
        "ao": "AO",
        "vinted": "Vinted",
        "depop": "Depop",
        "reverb": "Reverb",
        "discogs": "Discogs"
    ]

    static func retailer(forHost host: String) -> Retailer {
        let normalised = host.lowercased()
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)

        if let marketplace = AmazonMarketplace.matching(host: normalised) {
            return Retailer(name: "Amazon", domain: marketplace.domain)
        }

        let key = secondLevelName(of: normalised)
        if let known = knownRetailers[key] {
            return Retailer(name: known, domain: normalised)
        }
        return Retailer(name: prettified(key, fallback: normalised), domain: normalised)
    }

    /// "shop.johnlewis.com" -> "johnlewis"; "store.example.co.uk" -> "example".
    private static func secondLevelName(of host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        // Handle two-part public suffixes such as .co.uk, .com.au, .co.jp.
        let suffixHeads: Set<String> = ["co", "com", "net", "org", "gov", "ac"]
        if parts.count >= 3, suffixHeads.contains(parts[parts.count - 2]) {
            return parts[parts.count - 3]
        }
        return parts[parts.count - 2]
    }

    /// Turns "backmarket" into "Backmarket" rather than leaving a bare domain
    /// on screen. Multi-word names we know about live in the table above.
    private static func prettified(_ name: String, fallback: String) -> String {
        guard !name.isEmpty else { return fallback }
        let cleaned = name.replacingOccurrences(of: "-", with: " ")
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
