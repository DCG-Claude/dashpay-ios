import Network
import Combine

@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool
    @Published var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        // Set initial network status based on current path
        let currentPath = monitor.currentPath
        self.isConnected = currentPath.status == .satisfied
        self.connectionType = currentPath.usedInterfaceType
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.usedInterfaceType
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}