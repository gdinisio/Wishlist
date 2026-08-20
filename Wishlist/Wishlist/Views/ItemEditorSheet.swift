//
//  ItemEditorSheet.swift
//  Wishlist
//
//  One form, used everywhere an item is written by hand: adding without a link,
//  correcting what a lookup got wrong, or filling in what it could not find.
//

import SwiftUI
import Foundation

nonisolated enum ItemEditorMode {
    /// Edit an item already on the wishlist. Saving writes it back.
    case edit(WishlistItem)
    /// Edit a copy. Saving hands it to the caller.
    case draft(WishlistItem, title: String, saveLabel: String)

    var item: WishlistItem {
        switch self {
        case .edit(let item): item
        case .draft(let item, _, _): item
        }
    }

    var title: String {
        switch self {
        case .edit: String(localized: "Edit Item")
        case .draft(_, let title, _): title
        }
    }

    var saveLabel: String {
        switch self {
        case .edit: String(localized: "Save")
        case .draft(_, _, let label): label
        }
    }
}

struct ItemEditorSheet: View {
    let mode: ItemEditorMode
    var onSave: ((WishlistItem) -> Void)?

    @Environment(WishlistRepository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WishlistItem
    @State private var priceText: String
    @State private var currencyCode: String
    @State private var urlText: String
    @FocusState private var isNameFocused: Bool

    init(mode: ItemEditorMode, onSave: ((WishlistItem) -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        let item = mode.item
        _draft = State(initialValue: item)
        _priceText = State(initialValue: Self.priceString(item.price))
        _currencyCode = State(initialValue: item.price?.currencyCode ?? Self.localCurrencyCode)
        _urlText = State(initialValue: item.productURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $draft.name, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isNameFocused)
                } header: {
                    Text("Name")
                } footer: {
                    if trimmedName.isEmpty {
                        Text("A name is required.")
                    }
                }

                Section {
                    HStack {
                        TextField(String(localized: "Price"), text: $priceText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(Text("Price"))
                        Divider()
                        Picker(String(localized: "Currency"), selection: $currencyCode) {
                            ForEach(currencyOptions, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(Text("Currency"))
                    }

                    Picker(selection: $draft.availability) {
                        ForEach(Availability.allCases, id: \.self) { value in
                            Label(value.label, systemImage: value.symbolName).tag(value)
                        }
                    } label: {
                        Text("Availability")
                    }
                } header: {
                    Text("Price and Availability")
                } footer: {
                    Text("Leave the price empty if you don’t know it. Wishlist won’t guess.")
                }

                Section {
                    TextField(String(localized: "Store"), text: retailerBinding)
                        .textInputAutocapitalization(.words)
                    TextField(String(localized: "Brand"), text: optionalBinding(\.brand))
                        .textInputAutocapitalization(.words)
                    TextField(String(localized: "Category"), text: optionalBinding(\.category))
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Where It’s From")
                }

                Section {
                    TextField(String(localized: "Link"), text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                } header: {
                    Text("Link")
                } footer: {
                    if !urlText.isEmpty && !URLValidator.looksLikeURL(urlText) {
                        Label(String(localized: "This doesn’t look like a web address."),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField(String(localized: "Notes"), text: optionalBinding(\.notes), axis: .vertical)
                        .lineLimit(1...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle(Text(mode.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveLabel) { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    // MARK: - Bindings

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text fields need a `String`; the model keeps optionals so "unknown" and
    /// "empty" stay different things.
    private func optionalBinding(_ keyPath: WritableKeyPath<WishlistItem, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    private var retailerBinding: Binding<String> {
        Binding(
            get: { draft.retailer?.name ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    draft.retailer = nil
                } else {
                    draft.retailer = Retailer(name: newValue, domain: draft.retailer?.domain)
                }
            }
        )
    }

    private var currencyOptions: [String] {
        var options = [
            "GBP", "USD", "EUR", "JPY", "CAD", "AUD", "NZD", "CHF", "SEK",
            "NOK", "DKK", "PLN", "CZK", "INR", "SGD", "HKD", "CNY", "KRW",
            "BRL", "MXN", "ZAR", "AED", "TRY", "ILS"
        ]
        if !options.contains(currencyCode) { options.insert(currencyCode, at: 0) }
        return options
    }

    // MARK: - Saving

    private func save() {
        var item = draft
        item.name = trimmedName
        item.price = PriceParser.parse(priceText, currencyHint: currencyCode)
        item.productURL = (try? URLValidator.validate(urlText))?.canonicalURL
        if item.productURL != nil, item.retailer == nil,
           let host = item.productURL?.host() {
            item.retailer = RetailerIdentifier.retailer(forHost: host)
        }
        item.recordPrice(item.price)
        item.touch()

        if let onSave {
            onSave(item)
        } else {
            repository.update(item)
        }
        dismiss()
    }

    private static func priceString(_ price: Money?) -> String {
        guard let price else { return "" }
        return price.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private static var localCurrencyCode: String {
        Locale.current.currency?.identifier.uppercased() ?? "USD"
    }
}

#Preview {
    ItemEditorSheet(mode: .edit(WishlistItem.sample))
        .withPreviewEnvironment()
}
