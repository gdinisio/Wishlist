//
//  Formatting.swift
//  Wishlist
//
//  Shared date phrasing, so "Added" reads the same everywhere.
//

import Foundation

nonisolated enum DateText {
    /// Recent dates read relatively ("3 days ago"); older ones read absolutely,
    /// which is how iOS itself presents timestamps.
    static func friendly(_ date: Date, reference: Date = .now) -> String {
        let interval = reference.timeIntervalSince(date)
        if interval < 60 { return String(localized: "Just now") }
        if interval < 60 * 60 * 24 * 7 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func exact(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    /// Section titles in the Obtained list, e.g. "August 2026".
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func byteCount(_ bytes: Int) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
