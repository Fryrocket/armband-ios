import Foundation
import Network
import Combine

/// Wi-Fi vs cellular. Dump tries LAN on Wi-Fi and the WAN MQTT port off-LAN.
@MainActor
final class NetworkPath: ObservableObject {
    static let shared = NetworkPath()

    @Published private(set) var isWifi = false
    @Published private(set) var isCellular = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isWifi = path.usesInterfaceType(.wifi)
                self?.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.fryrocket.armbandios.netpath"))
    }
}
