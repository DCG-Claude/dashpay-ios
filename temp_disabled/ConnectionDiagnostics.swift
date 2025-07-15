import Foundation
import DashSPVFFI
import os.log

/// Enhanced diagnostics for debugging connection issues
public class ConnectionDiagnostics {
    private static let logger = Logger(subsystem: "com.dash.sdk", category: "ConnectionDiagnostics")
    
    /// Run comprehensive connection diagnostics
    public static func runDiagnostics(for client: SPVClient) async -> DiagnosticReport {
        logger.info("🔍 Running connection diagnostics...")
        
        var report = DiagnosticReport()
        
        // 1. Check FFI initialization
        report.ffiStatus = checkFFIStatus()
        
        // 2. Check network connectivity
        report.networkStatus = await checkNetworkConnectivity()
        
        // 3. Check peer configuration
        report.peerConfiguration = checkPeerConfiguration(client.configuration)
        
        // 4. Test peer connectivity
        report.peerConnectivity = await testPeerConnectivity(client.configuration)
        
        // 5. Check data directory
        report.dataDirectoryStatus = checkDataDirectory(client.configuration)
        
        // 6. Check for common issues
        report.commonIssues = checkCommonIssues(client)
        
        logger.info("✅ Diagnostics complete")
        return report
    }
    
    private static func checkFFIStatus() -> FFIStatus {
        var status = FFIStatus()
        
        status.initialized = FFIInitializer.initialized
        
        // Check FFI version
        if let versionPtr = dash_spv_ffi_version() {
            status.version = String(cString: versionPtr)
        } else {
            status.version = "NOT LOADED"
        }
        
        // Check for FFI errors
        if let errorPtr = dash_spv_ffi_get_last_error() {
            status.lastError = String(cString: errorPtr)
            dash_spv_ffi_clear_error()
        }
        
        // Check FFI library symbols
        status.symbolsLoaded = checkFFISymbols()
        
        return status
    }
    
    private static func checkFFISymbols() -> Bool {
        // Try to call a simple FFI function to verify library is loaded
        let testPtr = dash_spv_ffi_version()
        return testPtr != nil
    }
    
    private static func checkNetworkConnectivity() async -> NetworkStatus {
        var status = NetworkStatus()
        
        // Check system network status
        let monitor = NetworkMonitor()
        status.isConnected = await monitor.isConnected
        status.connectionType = monitor.connectionType?.description ?? "Unknown"
        
        // Test DNS resolution for common testnet seeds
        status.dnsResolution = await testDNSResolution()
        
        return status
    }
    
    private static func testDNSResolution() async -> [String: Bool] {
        let testnetSeeds = [
            "testnet-seed.dash.org",
            "testnet.dnsseed.dash.org",
            "seed-1.testnet.networks.dash.org"
        ]
        
        var results: [String: Bool] = [:]
        
        for seed in testnetSeeds {
            let host = seed.replacingOccurrences(of: ":19999", with: "")
            results[host] = await canResolveHost(host)
        }
        
        return results
    }
    
    private static func canResolveHost(_ host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            CFHostStartInfoResolution(host, .addresses, nil)
            var success = DarwinBoolean(false)
            let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray?
            continuation.resume(returning: success.boolValue && addresses != nil && addresses!.count > 0)
        }
    }
    
    private static func checkPeerConfiguration(_ config: SPVClientConfiguration) -> PeerConfigurationStatus {
        var status = PeerConfigurationStatus()
        
        status.network = config.network.name
        status.configuredPeers = config.additionalPeers
        status.maxPeers = Int(config.maxPeers)
        
        // Validate peer addresses
        for peer in config.additionalPeers {
            let components = peer.split(separator: ":")
            if components.count == 2, let port = Int(components[1]) {
                let expectedPort = config.network == .testnet ? 19999 : 9999
                if port != expectedPort {
                    status.warnings.append("Peer \(peer) has unexpected port for \(config.network.name)")
                }
            } else {
                status.warnings.append("Invalid peer address format: \(peer)")
            }
        }
        
        return status
    }
    
    private static func testPeerConnectivity(_ config: SPVClientConfiguration) async -> [PeerConnectivityTest] {
        var results: [PeerConnectivityTest] = []
        
        // Test each configured peer
        for peer in config.additionalPeers {
            let startTime = Date()
            let components = peer.split(separator: ":")
            
            guard components.count == 2,
                  let port = Int(components[1]) else {
                results.append(PeerConnectivityTest(
                    peer: peer,
                    reachable: false,
                    responseTime: nil,
                    error: "Invalid peer format"
                ))
                continue
            }
            
            let host = String(components[0])
            
            // First try DNS resolution for domain names
            if !host.contains(".") || host.split(separator: ".").compactMap({ Int($0) }).count == 4 {
                // It's an IP address, test directly
                let reachable = await testTCPConnection(host: host, port: port)
                results.append(PeerConnectivityTest(
                    peer: peer,
                    reachable: reachable,
                    responseTime: reachable ? Date().timeIntervalSince(startTime) : nil,
                    error: reachable ? nil : "Connection failed"
                ))
            } else {
                // It's a domain, resolve first
                if await canResolveHost(host) {
                    let reachable = await testTCPConnection(host: host, port: port)
                    results.append(PeerConnectivityTest(
                        peer: peer,
                        reachable: reachable,
                        responseTime: reachable ? Date().timeIntervalSince(startTime) : nil,
                        error: reachable ? nil : "Connection failed after DNS resolution"
                    ))
                } else {
                    results.append(PeerConnectivityTest(
                        peer: peer,
                        reachable: false,
                        responseTime: nil,
                        error: "DNS resolution failed"
                    ))
                }
            }
        }
        
        return results
    }
    
    private static func testTCPConnection(host: String, port: Int, timeout: TimeInterval = 5.0) async -> Bool {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "tcp.test")
            
            queue.async {
                var socketFD: Int32 = -1
                defer {
                    if socketFD >= 0 {
                        close(socketFD)
                    }
                }
                
                // Create socket
                socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Set non-blocking
                fcntl(socketFD, F_SETFL, O_NONBLOCK)
                
                // Create address
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(port).bigEndian
                
                // Convert host to address
                if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
                    // Try to resolve hostname
                    guard let hostent = gethostbyname(host),
                          hostent.pointee.h_addrtype == AF_INET else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    addr.sin_addr = hostent.pointee.h_addr_list.pointee!.withMemoryRebound(to: in_addr.self, capacity: 1) { $0.pointee }
                }
                
                // Try to connect
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                if result == 0 {
                    continuation.resume(returning: true)
                    return
                }
                
                if errno != EINPROGRESS {
                    continuation.resume(returning: false)
                    return
                }
                
                // Wait for connection with select
                var writeSet = fd_set()
                var errorSet = fd_set()
                // Clear fd_set structures
                memset(&writeSet, 0, MemoryLayout<fd_set>.size)
                memset(&errorSet, 0, MemoryLayout<fd_set>.size)
                // Set socket in fd_set
                withUnsafeMutablePointer(to: &writeSet) { ptr in
                    let index = Int(socketFD / 32)
                    let bit = socketFD % 32
                    ptr.pointee.__fds_bits.0 |= (1 << bit)
                }
                withUnsafeMutablePointer(to: &errorSet) { ptr in
                    let index = Int(socketFD / 32)
                    let bit = socketFD % 32
                    ptr.pointee.__fds_bits.0 |= (1 << bit)
                }
                
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                
                let selectResult = select(socketFD + 1, nil, &writeSet, &errorSet, &tv)
                
                if selectResult > 0 {
                    if __darwin_fd_isset(socketFD, &errorSet) {
                        continuation.resume(returning: false)
                    } else if __darwin_fd_isset(socketFD, &writeSet) {
                        // Check if really connected
                        var error: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                        continuation.resume(returning: error == 0)
                    } else {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private static func checkDataDirectory(_ config: SPVClientConfiguration) -> DataDirectoryStatus {
        var status = DataDirectoryStatus()
        
        if let dataDir = config.dataDirectory {
            status.path = dataDir.path
            status.exists = FileManager.default.fileExists(atPath: dataDir.path)
            
            if status.exists {
                // Check for sync state file
                let syncStateFile = dataDir.appendingPathComponent("sync_state.json")
                status.hasSyncState = FileManager.default.fileExists(atPath: syncStateFile.path)
                
                // Check directory permissions
                status.isWritable = FileManager.default.isWritableFile(atPath: dataDir.path)
                
                // Get directory size
                if let attributes = try? FileManager.default.attributesOfItem(atPath: dataDir.path) {
                    status.size = attributes[.size] as? Int64
                }
            }
        } else {
            status.path = "Not configured"
            status.exists = false
        }
        
        return status
    }
    
    private static func checkCommonIssues(_ client: SPVClient) -> [String] {
        var issues: [String] = []
        
        // Check for simulator-specific issues
        #if targetEnvironment(simulator)
        issues.append("Running on iOS Simulator - some network features may be limited")
        
        // Check if using localhost peers on simulator
        if client.configuration.additionalPeers.contains(where: { $0.contains("127.0.0.1") || $0.contains("localhost") }) {
            issues.append("Using localhost peers on simulator - ensure Docker/local node is accessible from simulator")
        }
        #endif
        
        // Check for testnet-specific issues
        if client.configuration.network == .testnet {
            if client.configuration.additionalPeers.isEmpty {
                issues.append("No testnet peers configured - relying on DNS seeds only")
            }
        }
        
        // Check for FFI issues
        if !FFIInitializer.initialized {
            issues.append("FFI not properly initialized - Core functionality will fail")
        }
        
        return issues
    }
}

// MARK: - Diagnostic Report Models

public struct DiagnosticReport {
    public var timestamp = Date()
    public var ffiStatus = FFIStatus()
    public var networkStatus = NetworkStatus()
    public var peerConfiguration = PeerConfigurationStatus()
    public var peerConnectivity: [PeerConnectivityTest] = []
    public var dataDirectoryStatus = DataDirectoryStatus()
    public var commonIssues: [String] = []
    
    public var summary: String {
        var output = "=== Connection Diagnostics Report ===\n"
        output += "Timestamp: \(timestamp)\n\n"
        
        output += "FFI Status:\n"
        output += "  - Initialized: \(ffiStatus.initialized)\n"
        output += "  - Version: \(ffiStatus.version ?? "Unknown")\n"
        output += "  - Symbols Loaded: \(ffiStatus.symbolsLoaded)\n"
        if let error = ffiStatus.lastError {
            output += "  - Last Error: \(error)\n"
        }
        output += "\n"
        
        output += "Network Status:\n"
        output += "  - Connected: \(networkStatus.isConnected)\n"
        output += "  - Type: \(networkStatus.connectionType)\n"
        output += "  - DNS Resolution:\n"
        for (host, resolved) in networkStatus.dnsResolution {
            output += "    - \(host): \(resolved ? "✅" : "❌")\n"
        }
        output += "\n"
        
        output += "Peer Configuration:\n"
        output += "  - Network: \(peerConfiguration.network)\n"
        output += "  - Max Peers: \(peerConfiguration.maxPeers)\n"
        output += "  - Configured Peers: \(peerConfiguration.configuredPeers.count)\n"
        for peer in peerConfiguration.configuredPeers {
            output += "    - \(peer)\n"
        }
        if !peerConfiguration.warnings.isEmpty {
            output += "  - Warnings:\n"
            for warning in peerConfiguration.warnings {
                output += "    ⚠️ \(warning)\n"
            }
        }
        output += "\n"
        
        output += "Peer Connectivity Tests:\n"
        let reachablePeers = peerConnectivity.filter { $0.reachable }.count
        output += "  - Reachable: \(reachablePeers)/\(peerConnectivity.count)\n"
        for test in peerConnectivity {
            if test.reachable {
                output += "  ✅ \(test.peer) - \(Int((test.responseTime ?? 0) * 1000))ms\n"
            } else {
                output += "  ❌ \(test.peer) - \(test.error ?? "Unknown error")\n"
            }
        }
        output += "\n"
        
        output += "Data Directory:\n"
        output += "  - Path: \(dataDirectoryStatus.path)\n"
        output += "  - Exists: \(dataDirectoryStatus.exists)\n"
        output += "  - Writable: \(dataDirectoryStatus.isWritable)\n"
        output += "  - Has Sync State: \(dataDirectoryStatus.hasSyncState)\n"
        if let size = dataDirectoryStatus.size {
            output += "  - Size: \(size) bytes\n"
        }
        output += "\n"
        
        if !commonIssues.isEmpty {
            output += "Common Issues Detected:\n"
            for issue in commonIssues {
                output += "  ⚠️ \(issue)\n"
            }
        }
        
        return output
    }
}

public struct FFIStatus {
    public var initialized = false
    public var version: String?
    public var lastError: String?
    public var symbolsLoaded = false
}

public struct NetworkStatus {
    public var isConnected = false
    public var connectionType = "Unknown"
    public var dnsResolution: [String: Bool] = [:]
}

public struct PeerConfigurationStatus {
    public var network = ""
    public var configuredPeers: [String] = []
    public var maxPeers = 0
    public var warnings: [String] = []
}

public struct PeerConnectivityTest {
    public var peer: String
    public var reachable: Bool
    public var responseTime: TimeInterval?
    public var error: String?
}

public struct DataDirectoryStatus {
    public var path = ""
    public var exists = false
    public var isWritable = false
    public var hasSyncState = false
    public var size: Int64?
}

// MARK: - SPVClient Extension

extension SPVClient {
    /// Get detailed peer connection information
    func getPeerConnectionInfo() -> String {
        var info = "Peer Connection Info:\n"
        info += "- Connected: \(isConnected)\n"
        info += "- Peer Count: \(peers)\n"
        info += "- FFI Client: \(ffiClient != nil ? "Created" : "Not created")\n"
        
        // Try to get more info from FFI if available
        if let client = ffiClient {
            // This would require FFI methods to get peer details
            info += "- FFI Client Active: Yes\n"
        }
        
        return info
    }
    
    /// Run comprehensive diagnostics
    public func runDiagnostics() async -> DiagnosticReport {
        return await ConnectionDiagnostics.runDiagnostics(for: self)
    }
}