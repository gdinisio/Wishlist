//
//  ImageDiskCache.swift
//  Wishlist
//
//  Product images change rarely and are re-shown constantly, so they are kept
//  on disk in the caches directory: instant on relaunch, offline-friendly, and
//  reclaimable by the system under storage pressure.
//

import Foundation
import CryptoKit
import OSLog

actor ImageDiskCache {
    private let directory: URL
    private let byteLimit: Int
    private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "images")

    init(byteLimit: Int = 96 * 1024 * 1024) {
        self.byteLimit = byteLimit
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("ProductImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return nil }
        // Touch so trimming keeps what is actually being used.
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))
        return data
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty else { return }
        try? data.write(to: fileURL(for: url), options: [.atomic])
    }

    func totalByteCount() -> Int {
        contents().reduce(0) { $0 + $1.size }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Drops the least recently used files once the cache exceeds its budget.
    func trimIfNeeded() {
        let files = contents()
        var total = files.reduce(0) { $0 + $1.size }
        guard total > byteLimit else { return }

        for file in files.sorted(by: { $0.modified < $1.modified }) {
            guard total > byteLimit else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
        log.debug("Trimmed image cache to \(total, privacy: .public) bytes")
    }

    private struct CachedFile {
        var url: URL
        var size: Int
        var modified: Date
    }

    private func contents() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return CachedFile(
                url: url,
                size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            )
        }
    }

    /// Hashed so any URL — however long or oddly punctuated — becomes a valid,
    /// collision-resistant file name.
    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}
