//
//  CurrencyRegion.swift
//  Wishlist
//
//  What currency a storefront trades in, worked out from its domain.
//
//  A shop at a country domain prices in that country's money — johnlewis.com
//  quotes pounds, amazon.de quotes euros. That is a fact about the shop, not a
//  guess about the product, which is why it is safe to lean on when a page
//  states an amount without saying what kind of money it is.
//

import Foundation

nonisolated enum CurrencyRegion {
    /// Longest suffixes first, so ".com.au" is matched before ".au" and
    /// ".co.uk" before ".uk".
    private static let suffixCurrencies: [(suffix: String, currency: String)] = [
        (".com.au", "AUD"), (".com.br", "BRL"), (".com.mx", "MXN"),
        (".com.tr", "TRY"), (".com.sg", "SGD"), (".co.uk", "GBP"),
        (".co.jp", "JPY"), (".co.nz", "NZD"), (".co.za", "ZAR"),
        (".co.in", "INR"), (".co.kr", "KRW"),
        (".uk", "GBP"), (".ie", "EUR"), (".de", "EUR"), (".fr", "EUR"),
        (".it", "EUR"), (".es", "EUR"), (".nl", "EUR"), (".be", "EUR"),
        (".at", "EUR"), (".fi", "EUR"), (".pt", "EUR"), (".gr", "EUR"),
        (".lu", "EUR"), (".sk", "EUR"), (".si", "EUR"), (".ee", "EUR"),
        (".lv", "EUR"), (".lt", "EUR"), (".cy", "EUR"), (".mt", "EUR"),
        (".se", "SEK"), (".no", "NOK"), (".dk", "DKK"), (".pl", "PLN"),
        (".cz", "CZK"), (".hu", "HUF"), (".ro", "RON"), (".bg", "BGN"),
        (".ch", "CHF"), (".ca", "CAD"), (".au", "AUD"), (".nz", "NZD"),
        (".jp", "JPY"), (".in", "INR"), (".sg", "SGD"), (".hk", "HKD"),
        (".cn", "CNY"), (".kr", "KRW"), (".br", "BRL"), (".mx", "MXN"),
        (".za", "ZAR"), (".ae", "AED"), (".sa", "SAR"), (".il", "ILS"),
        (".tr", "TRY"), (".th", "THB"), (".ph", "PHP"), (".my", "MYR"),
        (".id", "IDR"), (".vn", "VND"), (".ru", "RUB"), (".ua", "UAH"),
        (".ng", "NGN")
    ]

    /// The currency a host almost certainly prices in, or `nil` for domains
    /// that say nothing about country — `.com`, `.net`, `.io` and the like.
    static func currency(forHost host: String) -> String? {
        let normalised = host.lowercased()
        for entry in suffixCurrencies where normalised.hasSuffix(entry.suffix) {
            return entry.currency
        }
        return nil
    }
}
