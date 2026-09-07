import Foundation
import Network

/// iOS silently blocks TCP to LAN IPs until Local Network is allowed.
/// Browsing `_mqtt._tcp` (declared in Info.plist) is what actually pops the prompt.
@MainActor
final class LocalNetworkGate: ObservableObject {
    static let shared = LocalNetworkGate()

    @Published private(set) var statusText = ""

    private var browser: NWBrowser?

    func nudge() {
        if browser != nil { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_mqtt._tcp", domain: "local."), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.statusText = ""
                case .waiting:
                    self?.statusText = "Allow Local Network for Armband (Settings → Armband)"
                case .failed(let error):
                    self?.statusText = error.localizedDescription
                default:
                    break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }
}
