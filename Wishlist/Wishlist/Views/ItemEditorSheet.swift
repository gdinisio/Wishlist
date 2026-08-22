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
    @State private var isNamingCollection = false
    @State private var newCollectionName = ""
    @State private var isConfirmingDiscard = false
    @FocusState private var isPriceFocused: Bool

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
                            .focused($isPriceFocused)
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
                    TextField(String(localized: "Colour"), text: optionalBinding(\.colour))
                        .textInputAutocapitalization(.words)
                    TextField(String(localized: "Size"), text: optionalBinding(\.size))
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Which One")
                } footer: {
                    Text("The variant you actually want — useful in a shop, and when asking the assistant about it.")
                }

                Section {
                    Picker(selection: $draft.collectionName) {
                        Text("None").tag(String?.none)
                        ForEach(collectionOptions, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    } label: {
                        Text("Collection")
                    }

                    Button {
                        newCollectionName = ""
                        isNamingCollection = true
                    } label: {
                        Label(String(localized: "New Collection…"), systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Collection")
                } footer: {
                    Text("Optional. Group related things — a room, a person, an occasion.")
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
            .alert(String(localized: "New Collection"), isPresented: $isNamingCollection) {
                TextField(String(localized: "Name"), text: $newCollectionName)
                    .textInputAutocapitalization(.words)
                Button(String(localized: "Create")) {
                    let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { draft.collectionName = trimmed }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .navigationTitle(Text(mode.title))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                Text("Discard changes?"),
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Discard Changes"), role: .destructive) { dismiss() }
                Button(String(localized: "Keep Editing"), role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        if hasUnsavedChanges {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                // The decimal pad has no return key, so without this the
                // keyboard has no obvious way out.
                ToolbarItemGroup(placement: .keyboard) {
                    if isPriceFocused {
                        Spacer()
                        Button(String(localized: "Done")) { isPriceFocused = false }
                            .fontWeight(.semibold)
                    }
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

    /// Whether anything would be lost by leaving now. Drives both the swipe-to
    /// dismiss guard and the Cancel confirmation, so a half-finished edit is
    /// never thrown away by a stray gesture.
    private var hasUnsavedChanges: Bool {
        let original = mode.item
        return draft != original
            || priceText != Self.priceString(original.price)
            || currencyCode != (original.price?.currencyCode ?? Self.localCurrencyCode)
            || urlText != (original.productURL?.absoluteString ?? "")
    }

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

    /// Existing collections, plus whatever this item is already in, so a value
    /// created a moment ago is selectable before anything has been saved.
    private var collectionOptions: [String] {
        var names = Set(repository.collectionNames)
        if let current = draft.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty {
            names.insert(current)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var currencyOptions: [String] {
        CurrencyOptions.including(currencyCode)
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
