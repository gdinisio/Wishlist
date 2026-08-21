//
//  ClaudeClient.swift
//  Wishlist
//
//  Claude via the Messages API. Swift has no official Anthropic SDK, so this
//  speaks the REST endpoint directly through the app's own HTTPClient — which
//  means it inherits the same timeouts, status-code handling and error
//  vocabulary as every other network call in the app.
//
//  The answer is requested as a forced tool call rather than as prose: the
//  model must fill in a named schema, so the reply is a JSON object by
//  construction instead of by hope.
//

import Foundation

nonisolated struct ClaudeClient: LanguageModelClient {
    let displayName = String(localized: "Claude")

    private let http: HTTPClient
    private var apiKey: String = ""
    private var model: String = ClaudeModel.opus5.rawValue

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    init(http: HTTPClient) {
        self.http = http
    }

    func configured(apiKey: String, model: String) -> ClaudeClient {
        var copy = self
        copy.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model
        return copy
    }

    func answer(
        system: String,
        prompt: String,
        function: LanguageModelFunction,
        maxTokens: Int
    ) async throws -> JSONValue? {
        guard !apiKey.isEmpty else { throw LookupError.notAuthorized(provider: displayName) }

        let body: JSONValue = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            // Reading a page is simple work: low effort keeps latency and cost
            // down. Thinking is left adaptive — disabling it on Opus can make
            // the model narrate a tool call instead of making one.
            "output_config": ["effort": "low"],
            "system": .string(system),
            "messages": [
                ["role": "user", "content": .string(prompt)]
            ],
            "tools": [
                [
                    "name": .string(function.name),
                    "description": .string(function.purpose),
                    "input_schema": function.schema
                ]
            ],
            "tool_choice": ["type": "tool", "name": .string(function.name)]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try body.encoded()
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        let response = try await http.sendAllowingHTTPError(request, provider: displayName)
        guard (200...299).contains(response.statusCode) else {
            throw LanguageModelFailure.from(response, provider: displayName)
        }
        guard let json = JSONValue.parse(response.data) else {
            throw LookupError.providerUnavailable(provider: displayName)
        }

        // A safety decline arrives as a 200 with this stop reason, not as an
        // error. There is nothing to salvage, and nothing to apologise for.
        if json["stop_reason"]?.stringValue == "refusal" { return nil }

        for block in json["content"]?.arrayValue ?? [] where block["type"]?.stringValue == "tool_use" {
            if let input = block["input"] { return input }
        }
        return nil
    }
}
