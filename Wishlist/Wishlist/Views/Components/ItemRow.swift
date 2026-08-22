//
//  ItemRow.swift
//  Wishlist
//
//  One line of the wishlist. Ordered by what the eye needs first: picture,
//  name, then price. At accessibility text sizes the same information stacks
//  instead of being squeezed.
//

import SwiftUI
import Foundation

struct ItemRow: View {
    let item: WishlistItem
    var showsObtainedDate: Bool = false

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProductThumbnail(url: item.imageURL, size: thumbnailSize)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details
                    priceText
                }
            } else {
                details
                Spacer(minLength: 8)
                priceText
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.displayName)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if let retailer = item.displayRetailer {
                    Text(retailer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsObtainedDate, let obtained = item.dateObtained {
                    Text(DateText.friendly(obtained))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            secondaryStatus
        }
    }

    @ViewBuilder
    private var secondaryStatus: some View {
        if let change = item.priceChange, !item.isObtained {
            PriceChangeLabel(change: change)
        } else if item.availability.isNoteworthy, !item.isObtained {
            AvailabilityBadge(availability: item.availability, isCompact: true)
        } else if let variant = item.variantSummary {
            Text(variant)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var priceText: some View {
        if let price = item.price {
            Text(price.formatted)
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else {
            // An unknown price is stated, never implied by a blank space.
            Text("No price")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// One sentence that reads naturally, instead of four disconnected labels.
    private var accessibilityLabel: String {
        var parts: [String] = [item.displayName]
        if let retailer = item.displayRetailer {
            parts.append(String(localized: "from \(retailer)"))
        }
        if let price = item.price {
            parts.append(price.accessibleDescription)
        } else {
            parts.append(String(localized: "price unavailable"))
        }
        if showsObtainedDate, let obtained = item.dateObtained {
            parts.append(String(localized: "obtained \(DateText.friendly(obtained))"))
        } else if item.availability.isNoteworthy {
            parts.append(item.availability.label)
        }
        if let change = item.priceChange, !item.isObtained {
            parts.append(change.label)
        }
        if let variant = item.variantSummary {
            parts.append(variant)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    List {
        ForEach(WishlistItem.samples) { item in
            ItemRow(item: item)
        }
    }
    .listStyle(.plain)
}
