//
//  IntelligenceSettingsView.swift
//  Wishlist
//
//  Optional language-model assistance. Off by default, explained in plain
//  words, and scoped: the screen says exactly what leaves the device, when, and
//  what it costs.
//

import SwiftUI
import Foundation

struct IntelligenceSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var tester = ConnectionTester()
    @State private var groqModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: LookupError?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker(selection: $settings.intelligenceProvider) {
                    ForEach(IntelligenceProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                } label: {
                    Text("Assistant")
                }
                .pickerStyle(.inline)
                .accessibilityLabel(Text("Assistant provider"))
            } footer: {
                Text("Some stores publish nothing an app can read. An assistant can read the page the way you would, and point at the name and price it finds there.")
            }

            switch settings.intelligenceProvider {
            case .off:
                EmptyView()
            case .claude:
                claudeSection
            case .groq:
                groqSection
            }

            if settings.intelligenceProvider != .off {
                permissionsSection
                testSection
                assuranceSection
            }
        }
        .navigationTitle(Text("Assistant"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.intelligence) { _, _ in tester.reset() }
        .task {
            guard settings.intelligenceProvider == .groq else { return }
            await loadGroqModels()
        }
    }

    // MARK: - Providers

    @ViewBuilder
    private var claudeSection: some View {
        @Bindable var settings = settings

        Section {
            SecureField(String(localized: "API Key"), text: $settings.claudeKey)
                .textContentType(.password)

            Picker(selection: $settings.claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            } label: {
                Text("Model")
            }
        } header: {
            Text("Claude")
        } footer: {
            Text("\(settings.claudeModel.priceDescription). Claude's API is paid — a page read costs a fraction of a penny, and only happens when a store can't be read any other way. Keys come from console.anthropic.com.")
        }
    }

    @ViewBuilder
    private var groqSection: some View {
        @Bindable var settings = settings

        Section {
            SecureField(String(localized: "API Key"), text: $settings.groqKey)
                .textContentType(.password)

            if groqModels.isEmpty {
                // Fallback while the list is unknown, so a working key is never
                // blocked by a failed lookup of what it can reach.
                TextField(String(localized: "Model"), text: $settings.groqModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } else {
                Picker(selection: $settings.groqModel) {
                    ForEach(groqModels, id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                } label: {
                    Text("Model")
                }
            }

            Button {
                Task { await loadGroqModels() }
            } label: {
                if isLoadingModels {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking which models your key can use…")
                    }
                } else {
                    Label(
                        groqModels.isEmpty
                            ? String(localized: "Load Available Models")
                            : String(localized: "Reload Models"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .disabled(isLoadingModels || settings.groqKey.trimmingCharacters(in: .whitespaces).isEmpty)

            if let modelLoadError {
                InlineMessage(
                    symbolName: modelLoadError.symbolName,
                    title: modelLoadError.title,
                    message: modelLoadError.guidance,
                    tint: .orange
                )
            }
        } header: {
            Text("Groq")
        } footer: {
            Text("Groq has a free tier, which keeps Wishlist free end to end. Keys come from console.groq.com. Groq retires models regularly, so the list is read from your key rather than fixed in the app.")
        }
    }

    // MARK: - Scope

    private var permissionsSection: some View {
        @Bindable var settings = settings

        return Section {
            Toggle(isOn: $settings.readsDifficultPages) {
                Label(String(localized: "Read Difficult Pages"), systemImage: "doc.text.magnifyingglass")
            }
            Toggle(isOn: $settings.shortensTitles) {
                Label(String(localized: "Shorten Long Titles"), systemImage: "textformat.size.smaller")
            }
            Toggle(isOn: $settings.suggestsCategories) {
                Label(String(localized: "Suggest Categories"), systemImage: "tag")
            }
        } header: {
            Text("What It May Do")
        } footer: {
            Text("Titles are shortened using only words the store's own title already contains, and the full title is kept on the item's screen. Categories come from a fixed list.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                Label(String(localized: "Test Connection"), systemImage: "checkmark.seal")
            }
            .disabled(!settings.intelligence.isConfigured || tester.outcome == .testing)

            ConnectionResultView(outcome: tester.outcome)
        }
    }

    private var assuranceSection: some View {
        Section {
            InlineMessage(
                symbolName: "checkmark.shield",
                title: String(localized: "Nothing Is Invented"),
                message: String(localized: "Every value the assistant reports is looked for in the page's own text before Wishlist accepts it. A price that isn't on the page is discarded, not shown."),
                tint: .green
            )
            InlineMessage(
                symbolName: "hand.raised",
                title: String(localized: "What Gets Sent"),
                message: String(localized: "Only the text of the page you're adding, and its link. Your wishlist is never sent. Keys stay in this device's Keychain."),
                tint: .secondary
            )
        }
    }

    /// Asks Groq what this key can actually reach. A model the app shipped as a
    /// default may since have been retired, so the truthful list comes from the
    /// provider, not from us.
    private func loadGroqModels() async {
        let key = settings.groqKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isLoadingModels else { return }

        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }

        let client = GroqClient(http: URLSessionHTTPClient())
            .configured(apiKey: key, model: settings.groqModel)
        do {
            let identifiers = try await client.availableModels()
            groqModels = identifiers
            // A saved model the provider no longer offers is quietly replaced
            // with one it does — the picker makes the new value visible.
            if let first = identifiers.first, !identifiers.contains(settings.groqModel) {
                settings.groqModel = first
            }
        } catch let error as LookupError {
            modelLoadError = error
        } catch {
            modelLoadError = .providerUnavailable(provider: "Groq")
        }
    }

    private func runTest() {
        let configuration = settings.intelligence
        Task {
            guard let client = LanguageModelRouter(http: URLSessionHTTPClient())
                .client(for: configuration) else { return }
            await tester.test(model: client)
        }
    }
}

#Preview {
    NavigationStack {
        IntelligenceSettingsView()
    }
    .withPreviewEnvironment()
}
