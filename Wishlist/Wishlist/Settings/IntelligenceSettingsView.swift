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

            TextField(String(localized: "Model"), text: $settings.groqModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Groq")
        } footer: {
            Text("Groq has a free tier, which keeps Wishlist free end to end. Keys come from console.groq.com. Leave the model as \(IntelligenceSettings.defaultGroqModel) unless you have a reason to change it.")
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
