//
//  RemoteImage.swift
//  Wishlist
//
//  Product imagery. Loads off the main thread, decodes at the size it will be
//  drawn, and falls back to a neutral placeholder — a missing image should look
//  deliberate, not broken.
//

import SwiftUI
import Foundation
import UIKit

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// The largest dimension this image will be drawn at, in points.
    var maxPixelSize: CGFloat = 240

    @State private var image: UIImage?
    @State private var didFail = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeIn(duration: 0.18), value: image == nil)
            .task(id: taskIdentity) { await load() }
    }

    private var placeholder: some View {
        Image(systemName: didFail ? "photo.badge.exclamationmark" : "photo")
            .font(.system(size: min(maxPixelSize * 0.28, 34), weight: .light))
            .foregroundStyle(.tertiary)
    }

    private var taskIdentity: String {
        "\(url?.absoluteString ?? "none")|\(Int(maxPixelSize))"
    }

    private func load() async {
        guard let url else {
            image = nil
            didFail = false
            return
        }
        // A cache hit avoids a round trip and any visible placeholder.
        if let cached = ImageMemoryCache.shared.image(for: url, size: maxPixelSize) {
            image = cached
            didFail = false
            return
        }
        image = nil
        didFail = false
        do {
            let loaded = try await ImageLoader.shared.image(
                for: url,
                maxPixelSize: maxPixelSize,
                scale: displayScale
            )
            ImageMemoryCache.shared.insert(loaded, for: url, size: maxPixelSize)
            image = loaded
        } catch {
            didFail = true
        }
    }
}

/// A product thumbnail: square, subtly bounded so a white-background product
/// photo still reads as an image rather than as a hole in the list.
struct ProductThumbnail: View {
    let url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        RemoteImage(url: url, contentMode: .fill, maxPixelSize: size)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
