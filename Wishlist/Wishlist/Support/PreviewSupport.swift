//
//  PreviewSupport.swift
//  Wishlist
//
//  Sample data and an in-memory environment, so every screen has a preview
//  that shows a real, populated state.
//

import SwiftUI
import Foundation

extension AppEnvironment {
    /// One shared preview environment. Building a fresh one on every body
    /// evaluation would reset the store under the preview and churn forever.
    static let previewShared: AppEnvironment = .preview()
}

extension View {
    /// Injects a fully in-memory app environment for previews.
    func withPreviewEnvironment() -> some View {
        let environment = AppEnvironment.previewShared
        return self
            .environment(environment.repository)
            .environment(environment.settings)
            .environment(environment.network)
            .environment(environment.router)
            .environment(environment.alerts)
            .environment(\.productLookup, environment.lookup)
            .environment(\.productSearch, environment.search)
            .task { await environment.repository.load() }
    }
}

nonisolated extension WishlistItem {
    /// Stable across accesses so a preview that navigates by identifier
    /// finds the item it was given.
    static let samples: [WishlistItem] = {
        [
            WishlistItem(
                name: "Sony WH-1000XM5 Wireless Noise Cancelling Headphones",
                imageURL: URL(string: "https://m.media-amazon.com/images/I/61+btTzpJBL._AC_SL1500_.jpg"),
                productURL: URL(string: "https://www.amazon.co.uk/dp/B09XS7JWHH"),
                price: Money(amount: Decimal(string: "249.00") ?? 0, currencyCode: "GBP"),
                retailer: Retailer(name: "Amazon", domain: "amazon.co.uk"),
                availability: .inStock,
                brand: "Sony",
                category: "Headphones",
                details: "Industry-leading noise cancellation with eight microphones and Auto NC Optimizer.",
                dateAdded: .now.addingTimeInterval(-86_400 * 3),
                priceHistory: [
                    PricePoint(date: .now.addingTimeInterval(-86_400 * 3), price: Money(amount: Decimal(string: "289.00") ?? 0, currencyCode: "GBP")),
                    PricePoint(date: .now, price: Money(amount: Decimal(string: "249.00") ?? 0, currencyCode: "GBP"))
                ],
                dateRefreshed: .now,
                sources: ["Amazon"]
            ),
            WishlistItem(
                name: "Ember Mug² Travel",
                productURL: URL(string: "https://www.johnlewis.com/ember-travel-mug/p4923119"),
                price: Money(amount: Decimal(string: "179.95") ?? 0, currencyCode: "GBP"),
                retailer: Retailer(name: "John Lewis", domain: "johnlewis.com"),
                availability: .limited,
                brand: "Ember",
                dateAdded: .now.addingTimeInterval(-86_400 * 9),
                notes: "Black, 355 ml version.",
                sources: ["Product page"]
            ),
            WishlistItem(
                name: "LEGO Icons Botanical Orchid",
                imageURL: URL(string: "https://www.lego.com/cdn/cs/set/assets/orchid.jpg"),
                productURL: URL(string: "https://www.lego.com/en-gb/product/orchid-10311"),
                retailer: Retailer(name: "LEGO", domain: "lego.com"),
                availability: .outOfStock,
                brand: "LEGO",
                category: "Building Sets",
                dateAdded: .now.addingTimeInterval(-86_400 * 21)
            ),
            WishlistItem(
                name: "Kindle Paperwhite Signature Edition",
                productURL: URL(string: "https://www.amazon.co.uk/dp/B08N36XNTT"),
                price: Money(amount: Decimal(string: "179.99") ?? 0, currencyCode: "GBP"),
                retailer: Retailer(name: "Amazon", domain: "amazon.co.uk"),
                availability: .inStock,
                brand: "Amazon",
                dateAdded: .now.addingTimeInterval(-86_400 * 40),
                dateObtained: .now.addingTimeInterval(-86_400 * 12),
                status: .obtained,
                sources: ["Amazon"]
            ),
            WishlistItem(
                name: "Muji Gel Ink Pens, Pack of 10",
                price: Money(amount: Decimal(string: "12.50") ?? 0, currencyCode: "GBP"),
                retailer: Retailer(name: "Muji", domain: "muji.eu"),
                availability: .inStock,
                dateAdded: .now.addingTimeInterval(-86_400 * 60),
                dateObtained: .now.addingTimeInterval(-86_400 * 55),
                status: .obtained
            )
        ]
    }()

    static var sample: WishlistItem { samples[0] }
}
