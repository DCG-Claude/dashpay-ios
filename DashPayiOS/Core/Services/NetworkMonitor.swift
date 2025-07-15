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
        self.connectionType = Self.getConnectionType(from: currentPath)
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = Self.getConnectionType(from: path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private static func getConnectionType(from path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return .other
        }
    }
    
    deinit {
        monitor.cancel()
    }
}