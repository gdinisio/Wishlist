//
//  ImageLoader.swift
//  Wishlist
//
//  Loads product images without ever blocking the main thread, and without
//  decoding a 2000-pixel photograph to fill a 60-point thumbnail. Requests for
//  the same image are shared, results are cached in memory and on disk.
//

import Foundation
import UIKit
import ImageIO
import CoreGraphics

nonisolated final class ImageLoader: Sendable {
    static let shared = ImageLoader()

    private let session: URLSession
    private let disk: ImageDiskCache
    private let coalescer = TaskCoalescer<Data>()

    init(session: URLSession? = nil, disk: ImageDiskCache = ImageDiskCache()) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
        self.disk = disk
    }

    /// Returns a decoded image sized for how it will actually be drawn.
    func image(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) async throws -> UIImage {
        let data = try await data(for: url)
        guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize, scale: scale) else {
            throw LookupError.noProductData
        }
        return image
    }

    private func data(for requestedURL: URL) async throws -> Data {
        // Product pages still publish plain-http image URLs; App Transport
        // Security would refuse them, and every image CDN worth using serves
        // the same asset over TLS.
        let url = Self.secured(requestedURL)
        if let cached = await disk.data(for: url) { return cached }

        let disk = self.disk
        let session = self.session
        return try await coalescer.run(key: url.absoluteString, priority: .utility) {
            // Another caller may have finished while this one waited.
            if let cached = await disk.data(for: url) { return cached }

            var request = URLRequest(url: url)
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                             forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  !data.isEmpty
            else { throw LookupError.notFound }

            await disk.store(data, for: url)
            await disk.trimIfNeeded()
            return data
        }
    }

    /// Rewrites an `http` image URL to `https`.
    static func secured(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    func clearCache() async {
        await disk.removeAll()
    }

    func cacheSize() async -> Int {
        await disk.totalByteCount()
    }

    /// Decodes straight to the size needed. Downsampling in ImageIO keeps peak
    /// memory proportional to the thumbnail, not to the source image, which is
    /// what makes a long list scroll smoothly.
    static func downsample(data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let pixelSize = max(maxPixelSize * scale, 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

/// Decoded images, kept in memory so a row returning on screen is instant.
/// Bounded by count and by cost, and emptied automatically under pressure.
@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL, size: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, size))
    }

    func insert(_ image: UIImage, for url: URL, size: CGFloat) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key(url, size), cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func key(_ url: URL, _ size: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(size))" as NSString
    }
}
