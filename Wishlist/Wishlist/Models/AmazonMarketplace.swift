//
//  AmazonMarketplace.swift
//  Wishlist
//
//  Amazon is one API with fourteen front doors. This maps a storefront domain
//  to everything the Product Advertising API needs: signing region, endpoint
//  host, marketplace identifier — plus the currency that marketplace trades in,
//  used only to disambiguate a price whose symbol is ambiguous (a "$" on
//  amazon.ca is a Canadian dollar).
//

import Foundation

nonisolated enum AmazonMarketplace: String, CaseIterable, Codable, Sendable, Identifiable {
    case unitedStates = "www.amazon.com"
    case unitedKingdom = "www.amazon.co.uk"
    case germany = "www.amazon.de"
    case france = "www.amazon.fr"
    case italy = "www.amazon.it"
    case spain = "www.amazon.es"
    case netherlands = "www.amazon.nl"
    case sweden = "www.amazon.se"
    case poland = "www.amazon.pl"
    case belgium = "www.amazon.com.be"
    case ireland = "www.amazon.ie"
    case canada = "www.amazon.ca"
    case mexico = "www.amazon.com.mx"
    case brazil = "www.amazon.com.br"
    case japan = "www.amazon.co.jp"
    case australia = "www.amazon.com.au"
    case singapore = "www.amazon.sg"
    case india = "www.amazon.in"
    case unitedArabEmirates = "www.amazon.ae"
    case saudiArabia = "www.amazon.sa"
    case turkey = "www.amazon.com.tr"

    var id: String { rawValue }

    /// The `amazon.*` domain, without the `www.` prefix.
    var domain: String {
        String(rawValue.dropFirst("www.".count))
    }

    var displayName: String {
        switch self {
        case .unitedStates: String(localized: "United States")
        case .unitedKingdom: String(localized: "United Kingdom")
        case .germany: String(localized: "Germany")
        case .france: String(localized: "France")
        case .italy: String(localized: "Italy")
        case .spain: String(localized: "Spain")
        case .netherlands: String(localized: "Netherlands")
        case .sweden: String(localized: "Sweden")
        case .poland: String(localized: "Poland")
        case .belgium: String(localized: "Belgium")
        case .ireland: String(localized: "Ireland")
        case .canada: String(localized: "Canada")
        case .mexico: String(localized: "Mexico")
        case .brazil: String(localized: "Brazil")
        case .japan: String(localized: "Japan")
        case .australia: String(localized: "Australia")
        case .singapore: String(localized: "Singapore")
        case .india: String(localized: "India")
        case .unitedArabEmirates: String(localized: "United Arab Emirates")
        case .saudiArabia: String(localized: "Saudi Arabia")
        case .turkey: String(localized: "Türkiye")
        }
    }

    /// AWS region used to sign Product Advertising API requests.
    var signingRegion: String {
        switch self {
        case .unitedStates, .canada, .mexico, .brazil:
            "us-east-1"
        case .japan, .australia, .singapore:
            "us-west-2"
        default:
            "eu-west-1"
        }
    }

    var apiHost: String {
        "webservices." + domain
    }

    /// ISO 3166-1 alpha-2 country of this storefront. Some third-party readers
    /// key their results on the country rather than the domain.
    var countryCode: String {
        switch self {
        case .unitedStates: "US"
        case .unitedKingdom: "GB"
        case .germany: "DE"
        case .france: "FR"
        case .italy: "IT"
        case .spain: "ES"
        case .netherlands: "NL"
        case .sweden: "SE"
        case .poland: "PL"
        case .belgium: "BE"
        case .ireland: "IE"
        case .canada: "CA"
        case .mexico: "MX"
        case .brazil: "BR"
        case .japan: "JP"
        case .australia: "AU"
        case .singapore: "SG"
        case .india: "IN"
        case .unitedArabEmirates: "AE"
        case .saudiArabia: "SA"
        case .turkey: "TR"
        }
    }

    var currencyCode: String {
        switch self {
        case .unitedStates: "USD"
        case .unitedKingdom: "GBP"
        case .germany, .france, .italy, .spain, .netherlands, .belgium, .ireland: "EUR"
        case .sweden: "SEK"
        case .poland: "PLN"
        case .canada: "CAD"
        case .mexico: "MXN"
        case .brazil: "BRL"
        case .japan: "JPY"
        case .australia: "AUD"
        case .singapore: "SGD"
        case .india: "INR"
        case .unitedArabEmirates: "AED"
        case .saudiArabia: "SAR"
        case .turkey: "TRY"
        }
    }

    /// Matches a URL host such as "www.amazon.co.uk" or "smile.amazon.de".
    static func matching(host: String) -> AmazonMarketplace? {
        let normalised = host.lowercased()
        // Longest domain first so "amazon.com" does not shadow "amazon.com.au".
        return allCases
            .sorted { $0.domain.count > $1.domain.count }
            .first { normalised == $0.domain || normalised.hasSuffix("." + $0.domain) }
    }
}
