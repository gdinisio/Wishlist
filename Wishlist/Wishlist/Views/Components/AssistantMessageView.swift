//
//  AssistantMessageView.swift
//  Wishlist
//
//  Lays out an assistant reply: prose as formatted text, and a markdown table
//  as an actual table. `AttributedString` has no way to express a table, so a
//  reply that contains one would otherwise arrive as a wall of pipes.
//

import SwiftUI
import Foundation

struct AssistantMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(AssistantMarkdown.blocks(in: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let prose):
                    Text(AssistantMarkdown.formatted(prose))
                        .font(.body)
                        .multilineTextAlignment(.leading)
                case .table(let table):
                    AssistantTableView(table: table)
                }
            }
        }
    }
}

private struct AssistantTableView: View {
    let table: AssistantTable

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
            if !table.header.isEmpty {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(AssistantMarkdown.formatted(cell))
                            .font(.footnote.weight(.semibold))
                    }
                }
                Divider()
                    .gridCellColumns(table.columnCount)
            }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(AssistantMarkdown.formatted(cell))
                            .font(.footnote)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        // A table is a unit; reading it cell by cell in VoiceOver is worse than
        // hearing it once, in order.
        .accessibilityElement(children: .combine)
    }
}
