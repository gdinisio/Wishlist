//
//  AskAssistantSheet.swift
//  Wishlist
//
//  Ask about a product: alternatives, whether the price looks right, what to
//  check before buying.
//
//  The conversation is deliberately not saved. It is advice, not a record —
//  keeping it would imply the app stands behind it, and would put unverified
//  text next to the verified product data in the same file.
//

import SwiftUI
import Foundation

struct AskAssistantSheet: View {
    /// The item under discussion, or `nil` for a general question.
    var item: WishlistItem?

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var turns: [ChatTurn] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var failure: LookupError?
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let advisor = ShoppingAdvisor()

    var body: some View {
        NavigationStack {
            Group {
                if settings.intelligence.isConfigured {
                    conversation
                } else {
                    setupPrompt
                }
            }
            .navigationTitle(Text(item == nil ? "Ask" : "Ask About This"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .onDisappear { sendTask?.cancel() }
    }

    // MARK: - Not set up

    private var setupPrompt: some View {
        ContentUnavailableView {
            Label(String(localized: "Assistant Not Set Up"), systemImage: "sparkles")
        } description: {
            Text("Add a Groq or Claude key to ask about products, compare alternatives and sanity-check a price.")
        } actions: {
            // Pushed rather than sending the user to another tab: they can set
            // it up and come straight back to the question they had.
            NavigationLink {
                IntelligenceSettingsView()
            } label: {
                Text("Set Up Assistant")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty {
                        opening
                    }
                    ForEach(turns) { turn in
                        ChatTurnView(turn: turn).id(turn.id)
                    }
                    if isSending {
                        thinkingRow.id(Self.thinkingID)
                    }
                    if let failure {
                        InlineMessage(
                            symbolName: failure.symbolName,
                            title: failure.title,
                            message: failure.guidance,
                            tint: .orange
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: isSending) { _, _ in scrollToEnd(proxy) }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack(spacing: 10) {
                    ProductThumbnail(url: item.imageURL, size: 40, cornerRadius: 8)
                    Text(item.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                .padding(.bottom, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Asking about \(item.displayName)"))
            }

            ForEach(ShoppingAdvisor.starters(for: item), id: \.self) { starter in
                Button {
                    send(starter)
                } label: {
                    HStack {
                        Text(starter)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Thinking…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    item == nil
                        ? String(localized: "Ask about anything you’re thinking of buying")
                        : String(localized: "Ask about this item"),
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }

                Button {
                    send(draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canSend)
                .accessibilityLabel(Text("Send"))
            }

            // Always visible, because the caveat applies to every answer.
            Text("Suggestions come from the model’s own knowledge. Prices and stock aren’t checked.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Sending

    private static let thinkingID = "thinking"

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        guard let client = LanguageModelRouter(http: URLSessionHTTPClient())
            .client(for: settings.intelligence) else { return }

        draft = ""
        failure = nil
        turns.append(ChatTurn(role: .user, text: question))
        isSending = true

        let history = turns
        let subject = item
        let budget = settings.availableToSpend

        sendTask = Task {
            defer { isSending = false }
            do {
                let answer = try await advisor.reply(
                    to: history,
                    about: subject,
                    budget: budget,
                    client: client
                )
                guard !Task.isCancelled else { return }
                if let answer {
                    turns.append(ChatTurn(role: .assistant, text: answer))
                } else {
                    failure = .providerRejected(
                        provider: client.displayName,
                        detail: String(localized: "The model didn’t answer that one.")
                    )
                }
            } catch let error as LookupError {
                guard !Task.isCancelled, error != .cancelled else { return }
                failure = error
            } catch {
                guard !Task.isCancelled else { return }
                failure = .providerUnavailable(provider: client.displayName)
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.2)
        withAnimation(animation) {
            if isSending {
                proxy.scrollTo(Self.thinkingID, anchor: .bottom)
            } else if let last = turns.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }
}

/// One message. Restrained bubbles: the established iOS shape for a
/// conversation, without borrowing Messages' full visual language.
private struct ChatTurnView: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 44) }

            Text(turn.text)
                .font(.body)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(turn.role == .user ? Color.white : Color.primary)

            if turn.role == .assistant { Spacer(minLength: 44) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            turn.role == .user
                ? Text("You asked: \(turn.text)")
                : Text("Assistant: \(turn.text)")
        )
    }

    private var background: AnyShapeStyle {
        turn.role == .user
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(.quaternary)
    }
}

#Preview {
    AskAssistantSheet(item: WishlistItem.sample)
        .withPreviewEnvironment()
}
