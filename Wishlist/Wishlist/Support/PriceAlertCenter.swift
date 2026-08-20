//
//  PriceAlertCenter.swift
//  Wishlist
//
//  A wishlist that quietly watches prices is only useful if it can tell you
//  when one falls. These are local notifications, posted after a refresh has
//  actually observed a lower price than the one recorded before — never a
//  prediction, never a marketing nudge.
//
//  Permission is asked for the moment the user turns the feature on, and not
//  before: a prompt at launch, for something not yet wanted, is the wrong
//  trade of a scarce yes.
//

import Foundation
import Observation
import UserNotifications
import OSLog

@Observable
@MainActor
final class PriceAlertCenter {
    /// Mirrors the system setting so the UI can explain itself rather than
    /// silently doing nothing.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let centre = UNUserNotificationCenter.current()
    @ObservationIgnored private let log = Logger(subsystem: "com.gdinisio.Wishlist", category: "alerts")

    func refreshAuthorization() async {
        authorization = await centre.notificationSettings().authorizationStatus
    }

    /// Returns whether alerts can actually be delivered afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
            return granted
        } catch {
            log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            await refreshAuthorization()
            return false
        }
    }

    /// One notification per item that fell, delivered immediately.
    func announce(_ drops: [PriceDrop]) async {
        guard !drops.isEmpty, authorization == .authorized else { return }

        for drop in drops.prefix(5) {
            guard let saving = drop.saving, let now = drop.item.price else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Price drop")
            content.body = String(
                localized: "\(drop.item.displayName) is now \(now.formatted) — \(saving.formatted) less."
            )
            content.sound = .default
            content.interruptionLevel = .passive
            content.threadIdentifier = "price-drops"
            content.userInfo = ["itemID": drop.item.id.uuidString]

            // A nil trigger delivers now.
            let request = UNNotificationRequest(
                identifier: "drop-" + drop.item.id.uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await centre.add(request)
            } catch {
                log.notice("Could not post price-drop alert: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
