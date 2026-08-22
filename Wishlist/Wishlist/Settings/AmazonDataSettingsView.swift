//
//  AmazonDataSettingsView.swift
//  Wishlist
//
//  Setting up a third-party Amazon reader. The screen is written to be honest
//  about what this is: an optional, metered service you bring your own key to,
//  which buys reliability rather than any data the free reader cannot get.
//

import SwiftUI
import Foundation

struct AmazonDataSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var tester = ConnectionTester()
    @State private var usedThisMonth = 0

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker(selection: $settings.amazonDataService) {
                    ForEach(AmazonDataService.allCases) { service in
                        Text(service.displayName).tag(service)
                    }
                } label: {
                    Text("Service")
                }
                .pickerStyle(.inline)
            } footer: {
                Text(settings.amazonDataService.explanation)
            }

            if settings.amazonDataService != .off {
                credentialsSection
                scopeSection
                usageSection
                testSection
                cautionSection
            }
        }
        .navigationTitle(Text("Amazon Data"))
        .navigationBarTitleDisplayMode(.inline)
        .task { usedThisMonth = AmazonDataUsage.requestsThisMonth() }
        .onChange(of: settings.amazonData) { _, _ in tester.reset() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var credentialsSection: some View {
        @Bindable var settings = settings

        Section {
            if settings.amazonDataService.needsKey {
                SecureField(String(localized: "API Key"), text: $settings.amazonDataKey)
                    .textContentType(.password)
            }
            if settings.amazonDataService.needsActorIdentifier {
                TextField(String(localized: "Actor"), text: $settings.amazonDataActor)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
            if settings.amazonDataService.needsTemplate {
                TextField(String(localized: "Address"), text: $settings.amazonDataTemplate, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            }
            if let host = settings.amazonDataService.signupHost {
                Button {
                    if let url = URL(string: "https://" + host) { openURL(url) }
                } label: {
                    Label(String(localized: "Open \(host)"), systemImage: "safari")
                }
            }
        } header: {
            Text("Credentials")
        } footer: {
            Text(credentialsHelp)
        }
    }

    private var scopeSection: some View {
        @Bindable var settings = settings

        return Section {
            Toggle(isOn: $settings.amazonDataUsedForRefreshes) {
                Label(String(localized: "Use for Price Refreshes"), systemImage: "arrow.clockwise")
            }
        } footer: {
            Text("Refreshing every item spends the most credits. Turn this off to keep your allowance for adding items, where getting it right matters most — refreshes then fall back to reading the page.")
        }
    }

    private var usageSection: some View {
        Section {
            LabeledContent(String(localized: "Requests This Month")) {
                Text("\(usedThisMonth)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(String(localized: "Reset Count")) {
                AmazonDataUsage.reset()
                usedThisMonth = 0
            }
            .disabled(usedThisMonth == 0)
        } header: {
            Text("Usage")
        } footer: {
            Text("Counted on this device, so you can see roughly how much of a free allowance you have spent. It is not billing — check the service for the real figure.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                Label(String(localized: "Test Connection"), systemImage: "checkmark.seal")
            }
            .disabled(!settings.amazonData.isConfigured || tester.outcome == .testing)

            ConnectionResultView(outcome: tester.outcome)
        } footer: {
            Text("Looks up one real product, which spends one request.")
        }
    }

    private var cautionSection: some View {
        Section {
            InlineMessage(
                symbolName: "info.circle",
                title: String(localized: "What This Buys You"),
                message: String(localized: "Reliability, not new information. Wishlist already reads Amazon pages without any key — this mainly avoids the human checks Amazon shows to unfamiliar visitors."),
                tint: .secondary
            )
            InlineMessage(
                symbolName: "exclamationmark.triangle",
                title: String(localized: "Free Allowances Change"),
                message: String(localized: "These services alter their free tiers regularly. Check the current terms before relying on one, and keep an eye on the count above."),
                tint: .orange
            )
        }
    }

    private var credentialsHelp: String {
        switch settings.amazonDataService {
        case .off:
            return ""
        case .apify:
            return String(localized: "The actor is the scraper to run, written as username~actor-name. The default is a widely used Amazon product scraper; any actor that accepts a product URL will do.")
        case .hasData:
            return String(localized: "Your key from the service's dashboard.")
        case .custom:
            return String(localized: "Use {asin} and {domain} where those values belong, and include your key in the address. For example: https://example.com/product?key=abc&asin={asin}&domain={domain}")
        }
    }

    private func runTest() {
        let credentials = settings.credentials
        Task {
            await tester.test(
                provider: AmazonDataProvider(http: URLSessionHTTPClient()),
                request: LookupRequest(link: try? URLValidator.validate(Self.testProductURL)),
                credentials: credentials
            )
            usedThisMonth = AmazonDataUsage.requestsThisMonth()
        }
    }

    /// A long-lived, widely stocked product, used only to prove the key works.
    private static let testProductURL = "https://www.amazon.co.uk/dp/B08N5WRWNW"
}

#Preview {
    NavigationStack {
        AmazonDataSettingsView()
    }
    .withPreviewEnvironment()
}
