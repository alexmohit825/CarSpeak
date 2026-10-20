import Foundation
import Network

/// Monitors network reachability for CarSpeak without tearing down active Wireless CarPlay (Wi-Fi + 5G) sockets.
/// Relies on iOS `URLSessionConfiguration.multipathServiceType = .handover` for seamless interface switching,
/// and only notifies when recovering from a true `.unsatisfied` offline drop.
final class CellularHandoffMonitor: ObservableObject {
    @Published var currentInterface: String = "5G / Wi-Fi Ready"
    @Published var handoffCount: Int = 0
    @Published var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.AlexMohit.CarSpeak.CellularHandoffMonitor", qos: .userInteractive)
    private var wasOffline: Bool = false

    var onProactiveHandoffDetected: ((String) -> Void)?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let usesCellular = path.usesInterfaceType(.cellular)
            let usesWifi = path.usesInterfaceType(.wifi)
            let interfaceDesc = usesCellular ? "5G Cellular Multipath" : (usesWifi ? "Wi-Fi + 5G Standby" : "Offline")
            let satisfied = (path.status == .satisfied)

            DispatchQueue.main.async {
                self.isConnected = satisfied
                self.currentInterface = interfaceDesc
                // Only trigger socket recovery if we were truly offline (.unsatisfied) and just regained connectivity.
                // Never tear down an active socket when Wireless CarPlay Wi-Fi and 5G Cellular coexist.
                if self.wasOffline && satisfied {
                    self.handoffCount += 1
                    self.onProactiveHandoffDetected?(interfaceDesc)
                }
                self.wasOffline = !satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
