//
//  LanguageModel.swift
//  Wishlist
//
//  The seam for on-demand language models. Two rules govern everything behind
//  it:
//
//  1. A model is only ever asked to *read* — to find values that are already
//     written on a page, or to shorten wording that already exists. It is never
//     asked what something costs, or whether it is in stock.
//  2. Every value a model returns is checked against the source text before it
//     is accepted. Anything that cannot be found there is discarded.
//
//  A model failing is never a lookup failing: this layer is an enhancement, and
//  every call site treats a thrown error as "no extra information".
//

import Foundation

nonisolated enum IntelligenceProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case claude
    case groq

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .claude: String(localized: "Claude")
        case .groq: String(localized: "Groq")
        }
    }

    var symbolName: String {
        switch self {
        case .off: "minus.circle"
        case .claude, .groq: "sparkles"
        }
    }
}

/// Claude models offered in Settings, with the pricing shown alongside them so
/// the choice is made with the cost visible.
nonisolated enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case opus5 = "claude-opus-5"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus5: "Opus 5"
        case .sonnet5: "Sonnet 5"
        case .haiku45: "Haiku 4.5"
        }
    }

    /// Per million tokens, input / output.
    var priceDescription: String {
        switch self {
        case .opus5: String(localized: "$5 / $25 per million tokens")
        case .sonnet5: String(localized: "$3 / $15 per million tokens")
        case .haiku45: String(localized: "$1 / $5 per million tokens")
        }
    }
}

nonisolated struct IntelligenceSettings: Sendable, Equatable {
    var provider: IntelligenceProvider = .off
    var claudeKey: String?
    var claudeModel: ClaudeModel = .opus5
    var groqKey: String?
    var groqModel: String = IntelligenceSettings.defaultGroqModel

    /// Read a page the structured parsers could not.
    var readsDifficultPages: Bool = true
    /// Shorten keyword-stuffed product titles for the list.
    var shortensTitles: Bool = true
    /// Fill in a category when the retailer published none.
    var suggestsCategories: Bool = true

    /// Groq retires models on a schedule, so this is a starting point rather
    /// than a promise — Settings lists whatever the user's key can actually
    /// reach.
    static let defaultGroqModel = "openai/gpt-oss-120b"

    /// Identifiers shipped by earlier builds that Groq no longer serves. A
    /// stored value matching one of these is replaced rather than left to fail
    /// with a confusing error on the user's first lookup.
    static let retiredGroqModels: Set<String> = [
        "llama-3.3-70b-versatile",
        "llama-3.1-70b-versatile",
        "llama3-70b-8192",
        "llama3-8b-8192",
        "mixtral-8x7b-32768",
        "gemma-7b-it"
    ]

    var isConfigured: Bool {
        switch provider {
        case .off: false
        case .claude: !(claudeKey ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .groq: !(groqKey ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

/// A JSON-shaped answer requested from a model.
nonisolated struct LanguageModelFunction: Sendable {
    var name: String
    var purpose: String
    /// JSON Schema describing the object the model must return.
    var schema: JSONValue
}

nonisolated protocol LanguageModelClient: Sendable {
    var displayName: String { get }
    /// Returns the model's structured answer, or `nil` when it declined to
    /// answer at all.
    func answer(
        system: String,
        prompt: String,
        function: LanguageModelFunction,
        maxTokens: Int
    ) async throws -> JSONValue?
}

/// Turns a model service's non-2xx reply into an error that carries the
/// service's own explanation. A wrong model name, an expired plan or a
/// malformed request each say something specific, and repeating that verbatim
/// is far more use than anything generic written here.
nonisolated enum LanguageModelFailure {
    static func from(_ response: HTTPResponse, provider: String) -> LookupError {
        switch response.statusCode {
        case 401, 403:
            return .notAuthorized(provider: provider)
        case 429:
            let retryAfter = response.headerValue("Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .providerRejected(provider: provider, detail: message(in: response.data))
        }
    }

    /// Anthropic and Groq both nest their explanation under `error.message`.
    private static func message(in data: Data) -> String? {
        guard let json = JSONValue.parse(data),
              let text = json.value(at: "error.message")?.stringValue
        else { return nil }
        return text
    }
}

/// Picks the client the user configured. Returns `nil` when the feature is off
/// or unconfigured, which is how every call site short-circuits.
nonisolated struct LanguageModelRouter: Sendable {
    private let claude: ClaudeClient
    private let groq: GroqClient

    init(http: HTTPClient) {
        claude = ClaudeClient(http: http)
        groq = GroqClient(http: http)
    }

    func client(for settings: IntelligenceSettings) -> (any LanguageModelClient)? {
        guard settings.isConfigured else { return nil }
        switch settings.provider {
        case .off:
            return nil
        case .claude:
            guard let key = settings.claudeKey else { return nil }
            return claude.configured(apiKey: key, model: settings.claudeModel.rawValue)
        case .groq:
            guard let key = settings.groqKey else { return nil }
            return groq.configured(apiKey: key, model: settings.groqModel)
        }
    }
}
