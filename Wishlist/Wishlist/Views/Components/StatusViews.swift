//
//  StatusViews.swift
//  Wishlist
//
//  Small pieces of status. Every one pairs a symbol with a word: colour is a
//  reinforcement here, never the message itself.
//

import SwiftUI
import Foundation

struct AvailabilityBadge: View {
    let availability: Availability
    var isCompact: Bool = false

    var body: some View {
        Label {
            Text(availability.label)
        } icon: {
            Image(systemName: availability.symbolName)
        }
        .font(isCompact ? .caption : .subheadline)
        .foregroundStyle(tint)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(availability.label)
    }

    private var tint: Color {
        switch availability {
        case .inStock: .green
        case .outOfStock, .discontinued: .secondary
        case .limited, .preOrder: .orange
        case .unknown: .secondary
        }
    }
}

struct PriceChangeLabel: View {
    let change: PriceChange
    var isCompact: Bool = true

    var body: some View {
        Label {
            Text(isCompact ? change.compactLabel : change.label)
        } icon: {
            Image(systemName: change.symbolName)
        }
        .font(isCompact ? .caption.weight(.medium) : .subheadline)
        .foregroundStyle(change.isDrop ? Color.green : Color.secondary)
        .accessibilityLabel(change.label)
    }
}

/// Inline, non-modal feedback: an explanation plus, when there is one, a way
/// forward. Used instead of an alert wherever the app can stay out of the way.
struct InlineMessage: View {
    var symbolName: String
    var title: String
    var message: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A short confirmation with a way to take it back. Appears above the content,
/// dismisses itself, and never steals focus.
struct UndoBanner: View {
    let action: UndoableAction
    let undo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(action.message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(String(localized: "Undo"), action: undo)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.message)
        .accessibilityHint(String(localized: "Double tap Undo to reverse this change"))
    }
}

/// Offline notice used at the top of flows that need the network.
struct OfflineNotice: View {
    var body: some View {
        InlineMessage(
            symbolName: "wifi.slash",
            title: String(localized: "No Internet Connection"),
            message: String(localized: "You can still add an item by name and fill in the details later."),
            tint: .orange
        )
    }
}
