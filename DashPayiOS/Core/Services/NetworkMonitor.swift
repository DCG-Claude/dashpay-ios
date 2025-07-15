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
        // Get connection type from available interfaces
        if currentPath.usesInterfaceType(.wifi) {
            self.connectionType = .wifi
        } else if currentPath.usesInterfaceType(.cellular) {
            self.connectionType = .cellular
        } else if currentPath.usesInterfaceType(.wiredEthernet) {
            self.connectionType = .wiredEthernet
        } else {
            self.connectionType = .other
        }
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                // Get connection type from available interfaces
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = .other
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}