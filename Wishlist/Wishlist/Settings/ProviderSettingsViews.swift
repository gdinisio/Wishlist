//
//  ProviderSettingsViews.swift
//  Wishlist
//
//  One screen per lookup service. Each says plainly what it does, what it
//  needs, and — with one tap — whether the key actually works.
//

import SwiftUI
import Foundation
import Observation

/// Runs a single live request against a provider so the user gets a real
/// answer instead of "saved".
@Observable
@MainActor
final class ConnectionTester {
    nonisolated enum Outcome: Equatable {
        case idle
        case testing
        case success(String?)
        case failure(LookupError)
    }

    private(set) var outcome: Outcome = .idle

    func reset() {
        outcome = .idle
    }

    /// A deliberately trivial round trip: the model must return one fixed
    /// value into a schema. It proves the key, the model name and the network
    /// path without spending anything meaningful.
    func test(model client: any LanguageModelClient) async {
        outcome = .testing
        let function = LanguageModelFunction(
            name: "report_status",
            purpose: "Report that the connection works.",
            schema: [
                "type": "object",
                "properties": [
                    "status": ["type": "string", "enum": ["ready"]]
                ],
                "required": ["status"],
                "additionalProperties": false
            ]
        )
        do {
            let answer = try await client.answer(
                system: "You are being checked for connectivity.",
                prompt: "Report your status.",
                function: function,
                maxTokens: 64
            )
            if answer?["status"]?.stringValue == "ready" {
                outcome = .success(client.displayName)
            } else {
                outcome = .failure(.providerUnavailable(provider: client.displayName))
            }
        } catch let error as LookupError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.providerUnavailable(provider: client.displayName))
        }
    }

    func test(
        provider: any ProductDataProvider,
        request: LookupRequest,
        credentials: LookupCredentials
    ) async {
        outcome = .testing
        do {
            let snapshot = try await provider.fetch(request, credentials: credentials)
            outcome = .success(snapshot.name)
        } catch let error as LookupError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.providerUnavailable(provider: provider.displayName))
        }
    }
}

/// Shared presentation of a test result.
struct ConnectionResultView: View {
    let outcome: ConnectionTester.Outcome

    var body: some View {
        switch outcome {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Testing…")
                    .foregroundStyle(.secondary)
            }
        case .success(let name):
            InlineMessage(
                symbolName: "checkmark.circle.fill",
                title: String(localized: "Connected"),
                message: name.map { String(localized: "Found “\($0)”.") }
                    ?? String(localized: "The key was accepted."),
                tint: .green
            )
        case .failure(let error):
            InlineMessage(
                symbolName: error.symbolName,
                title: error.title,
                message: error.guidance,
                tint: .orange
            )
        }
    }
}

// MARK: - Amazon

struct AmazonSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var tester = ConnectionTester()

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField(String(localized: "Access Key"), text: $settings.amazonAccessKey)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                SecureField(String(localized: "Secret Key"), text: $settings.amazonSecretKey)
                    .textContentType(.password)
                TextField(String(localized: "Partner Tag"), text: $settings.amazonPartnerTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Credentials")
            } footer: {
                Text("Free to use — Amazon charges nothing per request. You do need an approved Amazon Associates account: sign up, then find these under Tools ▸ Product Advertising API. The partner tag is your Associates store ID.")
            }

            Section {
                Picker(selection: $settings.amazonMarketplace) {
                    ForEach(AmazonMarketplace.allCases) { marketplace in
                        Text(marketplace.displayName).tag(marketplace)
                    }
                } label: {
                    Text("Store")
                }
            } footer: {
                Text("Requests are signed for this store’s region. Amazon links you paste use whichever store they point at.")
            }

            Section {
                Button {
                    runTest()
                } label: {
                    Label(String(localized: "Test Connection"), systemImage: "checkmark.seal")
                }
                .disabled(!settings.credentials.hasAmazonPAAPI || tester.outcome == .testing)

                ConnectionResultView(outcome: tester.outcome)
            } footer: {
                Text("Sends one search request to check the credentials. No charge.")
            }
        }
        .navigationTitle(Text("Amazon"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.credentials) { _, _ in tester.reset() }
    }

    private func runTest() {
        let credentials = settings.credentials
        Task {
            await tester.test(
                provider: AmazonPAAPIProvider(http: URLSessionHTTPClient()),
                request: LookupRequest(link: nil, searchTerm: "wireless headphones"),
                credentials: credentials
            )
        }
    }
}

// MARK: - Microlink

struct MicrolinkSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                SecureField(String(localized: "API Key (optional)"), text: $settings.microlinkKey)
                    .textContentType(.password)
            } header: {
                Text("Credentials")
            } footer: {
                Text("Microlink recovers a name and picture from pages that refuse to be read directly. Wishlist uses its free tier, which needs no key and allows a small number of lookups per day. Leave this empty unless you already pay for a Microlink plan.")
            }
        }
        .navigationTitle(Text("Microlink"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AmazonSettingsView()
    }
    .withPreviewEnvironment()
}
