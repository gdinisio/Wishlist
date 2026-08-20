//
//  NetworkMonitor.swift
//  Wishlist
//
//  Connectivity, observed rather than discovered by failing. Lets the add flow
//  tell the user up front that a lookup won't work, instead of spinning for
//  fifteen seconds and then apologising.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isOnline: Bool = true

    // Internally thread-safe, and read from `deinit`, which is nonisolated.
    private nonisolated(unsafe) let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gdinisio.Wishlist.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
