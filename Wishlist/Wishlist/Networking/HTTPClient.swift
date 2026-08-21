//
//  HTTPClient.swift
//  Wishlist
//
//  The single seam between the app and the network. Everything above this file
//  works with `LookupError`; nothing above it sees a status code, a URLError or
//  a response body it did not ask for.
//

import Foundation

nonisolated struct HTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
    var headers: [String: String]
    var url: URL?

    func headerValue(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Injected wherever the network is needed, so providers can be exercised
/// against a stub without touching URLSession.
nonisolated protocol HTTPClient: Sendable {
    /// Sends a request, turning any non-2xx status into a `LookupError`.
    func send(_ request: URLRequest, provider: String) async throws -> HTTPResponse
    /// Sends a request and returns the response whatever its status, so a
    /// caller can read the service's own explanation out of an error body.
    /// Transport failures still throw.
    func sendAllowingHTTPError(_ request: URLRequest, provider: String) async throws -> HTTPResponse
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    /// Responses larger than this are almost certainly not a product page and
    /// are refused rather than being parsed, to keep memory flat.
    private let maximumResponseBytes: Int

    init(session: URLSession? = nil, maximumResponseBytes: Int = 4_000_000) {
        self.session = session ?? URLSessionHTTPClient.makeDefaultSession()
        self.maximumResponseBytes = maximumResponseBytes
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "wishlist-http"
        )
        return URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, provider: String) async throws -> HTTPResponse {
        let result = try await sendAllowingHTTPError(request, provider: provider)
        switch result.statusCode {
        case 200...299:
            return result
        case 401, 403:
            throw LookupError.notAuthorized(provider: provider)
        case 404, 410:
            throw LookupError.notFound
        case 408:
            throw LookupError.timedOut
        case 429:
            let retryAfter = result.headerValue("Retry-After").flatMap(TimeInterval.init)
            throw LookupError.rateLimited(retryAfter: retryAfter)
        default:
            throw LookupError.providerUnavailable(provider: provider)
        }
    }

    func sendAllowingHTTPError(_ request: URLRequest, provider: String) async throws -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw LookupError(urlError: error, provider: provider)
        } catch is CancellationError {
            throw LookupError.cancelled
        } catch {
            throw LookupError.providerUnavailable(provider: provider)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LookupError.providerUnavailable(provider: provider)
        }

        guard data.count <= maximumResponseBytes else {
            throw LookupError.noProductData
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }

        return HTTPResponse(
            data: data,
            statusCode: http.statusCode,
            headers: headers,
            url: http.url
        )
    }
}

nonisolated extension LookupError {
    init(urlError: URLError, provider: String) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotConnectToHost:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        case .cannotFindHost, .dnsLookupFailed, .unsupportedURL, .badURL:
            self = .unsupportedURL(host: urlError.failingURL?.host())
        case .fileDoesNotExist, .resourceUnavailable:
            self = .notFound
        default:
            self = .providerUnavailable(provider: provider)
        }
    }
}
