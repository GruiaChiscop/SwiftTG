// TelegramNetworkTypeMonitor.swift

import Foundation
import Network
@preconcurrency import TDLibKit

/// Tracks which TDLib `NetworkType` bucket the device is currently on, so auto-download gating
/// can pick the right cap without awaiting anything. No public API reliably reports cellular
/// roaming state, so roaming traffic is treated as ordinary `.networkTypeMobile` here - the
/// existing per-network-type Roaming settings screen still lets a user dial that down manually.
@MainActor final class TelegramNetworkTypeMonitor {
    // MARK: Lifecycle

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let type = Self.networkType(for: path)
            Task { @MainActor in self?.current = type }
        }
        monitor.start(queue: queue)
    }

    // MARK: Internal

    static let shared = TelegramNetworkTypeMonitor()

    private(set) var current = NetworkType.networkTypeWiFi

    // MARK: Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.auto-download-network")

    private nonisolated static func networkType(for path: NWPath) -> NetworkType {
        guard path.status == .satisfied else { return .networkTypeNone }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .networkTypeWiFi
        }
        if path.usesInterfaceType(.cellular) {
            return .networkTypeMobile
        }
        return .networkTypeOther
    }
}
