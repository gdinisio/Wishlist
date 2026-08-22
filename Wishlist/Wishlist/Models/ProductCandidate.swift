//
//  ProductCandidate.swift
//  Wishlist
//
//  One result of a search by name — enough to recognise a product and choose
//  it, and nothing more. Choosing one runs the normal lookup against its own
//  page, so what finally gets saved comes from the same verified chain as a
//  pasted link.
//

import Foundation

nonisolated struct ProductCandidate: Identifiable, Hashable, Sendable {
    /// The retailer's identifier where there is one (an ASIN), else the URL.
    var id: String
    var name: String
    var price: Money?
    var imageURL: URL?
    var productURL: URL
    var retailer: Retailer
}
