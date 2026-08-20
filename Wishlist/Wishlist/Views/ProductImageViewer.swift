//
//  ProductImageViewer.swift
//  Wishlist
//
//  A product photo, given the whole screen. Double tap to zoom, drag to move
//  around, Done to leave — the behaviour a photo has everywhere else on iOS,
//  so there is nothing to learn.
//

import SwiftUI
import Foundation

struct ProductImageViewer: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isZoomed = false
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let zoomScale: CGFloat = 2.5

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                RemoteImage(
                    url: url,
                    contentMode: .fit,
                    maxPixelSize: 1200,
                    placeholderFill: .clear
                )
                .scaleEffect(isZoomed ? zoomScale : 1)
                .offset(offset)
                .gesture(pan)
                .onTapGesture(count: 2) { toggleZoom() }
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text("Double tap with two fingers to zoom"))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: url) {
                        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Panning only means anything while zoomed in.
    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isZoomed else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func toggleZoom() {
        let change = {
            isZoomed.toggle()
            if !isZoomed {
                offset = .zero
                committedOffset = .zero
            }
        }
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.25)) { change() }
        }
    }
}
