//
//  GroqClient.swift
//  Wishlist
//
//  Groq's OpenAI-compatible endpoint, for the Llama models. Groq has a free
//  tier, which makes it the option that keeps the app free end to end.
//
//  These models have no forced-tool-call guarantee, so the schema is stated in
//  the prompt and JSON mode is requested. Whatever comes back is parsed
//  defensively and then verified against the page like every other answer.
//

import Foundation

nonisolated struct GroqClient: LanguageModelClient {
    let displayName = String(localized: "Groq")

    private let http: HTTPClient
    private var apiKey: String = ""
    private var model: String = IntelligenceSettings.defaultGroqModel

    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private static let modelsEndpoint = URL(string: "https://api.groq.com/openai/v1/models")!

    /// Model families that are not chat models, and would only clutter a picker.
    private static let excludedModelKeywords = ["whisper", "tts", "guard", "embed", "prompt-guard"]

    init(http: HTTPClient) {
        self.http = http
    }

    func configured(apiKey: String, model: String) -> GroqClient {
        var copy = self
        copy.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = trimmedModel.isEmpty ? IntelligenceSettings.defaultGroqModel : trimmedModel
        return copy
    }

    func answer(
        system: String,
        prompt: String,
        function: LanguageModelFunction,
        maxTokens: Int
    ) async throws -> JSONValue? {
        guard !apiKey.isEmpty else { throw LookupError.notAuthorized(provider: displayName) }

        let schemaText = String(data: (try? function.schema.encoded()) ?? Data(), encoding: .utf8) ?? "{}"
        // JSON mode requires the word "JSON" in the prompt, and the schema has
        // to be stated rather than enforced.
        let systemMessage = """
        \(system)

        Reply with a single JSON object and nothing else. It must match this JSON Schema:
        \(schemaText)
        """

        let body: JSONValue = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": .string(systemMessage)],
                ["role": "user", "content": .string(prompt)]
            ]
        ]

        guard let json = try await perform(body),
              let content = json.value(at: "choices.0.message.content")?.stringValue,
              let payload = JSONValue.parse(Data(content.utf8))
        else { return nil }

        return payload
    }

    func reply(system: String, turns: [ChatTurn], maxTokens: Int) async throws -> String? {
        guard !apiKey.isEmpty else { throw LookupError.notAuthorized(provider: displayName) }
        guard !turns.isEmpty else { return nil }

        var messages: [JSONValue] = [["role": "system", "content": .string(system)]]
        messages.append(contentsOf: turns.map { turn in
            ["role": .string(turn.role.rawValue), "content": .string(turn.text)]
        })

        let body: JSONValue = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            // Some warmth for advice, where extraction wants none.
            "temperature": .number(0.4),
            "messages": .array(messages)
        ]

        guard let json = try await perform(body) else { return nil }
        let text = json.value(at: "choices.0.message.content")?.stringValue
        return (text?.isEmpty ?? true) ? nil : text
    }

    private func perform(_ body: JSONValue) async throws -> JSONValue? {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try body.encoded()
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")

        let response = try await http.sendAllowingHTTPError(request, provider: displayName)
        guard (200...299).contains(response.statusCode) else {
            throw LanguageModelFailure.from(response, provider: displayName)
        }
        return JSONValue.parse(response.data)
    }

    /// The chat models this key can actually reach. Asking the provider beats
    /// hard-coding a list that goes stale the next time a model is retired —
    /// which is exactly how the previous default stopped working.
    func availableModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw LookupError.notAuthorized(provider: displayName) }

        var request = URLRequest(url: Self.modelsEndpoint)
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")

        let response = try await http.sendAllowingHTTPError(request, provider: displayName)
        guard (200...299).contains(response.statusCode) else {
            throw LanguageModelFailure.from(response, provider: displayName)
        }
        guard let json = JSONValue.parse(response.data) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }
        return (json["data"]?.arrayValue ?? [])
            .compactMap { $0["id"]?.stringValue }
            .filter { identifier in
                let lowered = identifier.lowercased()
                return !Self.excludedModelKeywords.contains { lowered.contains($0) }
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
