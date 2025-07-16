import Foundation
import Network
import DashSPVFFI

/// Comprehensive connection debugging tool
public class ConnectionDebugger {
    
    /// Run full diagnostics on the DashSDK connection
    public static func runFullDiagnostics(for sdk: DashSDK) async -> ConnectionDiagnosticReport {
        var report = ConnectionDiagnosticReport()
        report.timestamp = Date()
        
        print("\n=== DashPay Connection Diagnostics ===")
        print("Timestamp: \(report.timestamp)\n")
        
        // 1. FFI Status Check
        print("1️⃣ Checking FFI Status...")
        report.ffiCheck = checkFFIStatus()
        SyncDebugLogger.logFFIStatus()
        
        // 2. Network Status Check
        print("\n2️⃣ Checking Network Status...")
        report.networkCheck = await checkNetworkStatus()
        
        // 3. Configuration Check
        print("\n3️⃣ Checking Configuration...")
        report.configCheck = checkConfiguration(sdk.spvClient.configuration)
        SyncDebugLogger.logConfiguration(sdk.spvClient.configuration)
        
        // 4. Peer Connectivity Test
        print("\n4️⃣ Testing Peer Connectivity...")
        report.peerTests = await testPeerConnectivity(sdk.spvClient)
        
        // 5. Connection Test
        print("\n5️⃣ Testing Connection...")
        report.connectionTest = await testConnection(sdk)
        
        // 6. Sync Status
        print("\n6️⃣ Checking Sync Status...")
        report.syncStatus = checkSyncStatus(sdk.spvClient)
        
        // 7. Common Issues
        print("\n7️⃣ Checking for Common Issues...")
        report.commonIssues = checkCommonIssues(sdk)
        
        // Generate summary
        report.generateSummary()
        
        print("\n=== Diagnostics Complete ===\n")
        SyncDebugLogger.writeToFile(report.fullReport())
        
        return report
    }
    
    // MARK: - Individual Checks
    
    private static func checkFFIStatus() -> FFICheckResult {
        var result = FFICheckResult()
        
        // Check if initialized
        result.initialized = FFIInitializer.initialized
        
        // Check version
        if let versionPtr = dash_spv_ffi_version() {
            result.version = String(cString: versionPtr)
            result.libraryLoaded = true
        } else {
            result.version = "NOT LOADED"
            result.libraryLoaded = false
        }
        
        // Check for errors
        if let error = FFIBridge.getLastError() {
            result.lastError = error
        }
        
        // Test basic FFI call
        result.testCallSuccessful = testBasicFFICall()
        
        return result
    }
    
    private static func testBasicFFICall() -> Bool {
        // Try to create and destroy a simple FFI object
        guard let config = dash_spv_ffi_config_new(0, nil, nil, nil, 8, false, false) else {
            return false
        }
        dash_spv_ffi_config_destroy(config)
        return true
    }
    
    private static func checkNetworkStatus() async -> NetworkCheckResult {
        var result = NetworkCheckResult()
        
        // System network status
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "network.monitor")
        
        await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                result.isConnected = path.status == .satisfied
                result.connectionType = path.availableInterfaces.first.map { "\($0.type)" } ?? "None"
                result.isExpensive = path.isExpensive
                result.isConstrained = path.isConstrained
                monitor.cancel()
                continuation.resume()
            }
            monitor.start(queue: queue)
        }
        
        // DNS resolution tests
        result.dnsResults = await testDNSResolution()
        
        // Internet connectivity test
        result.internetReachable = await testInternetConnectivity()
        
        return result
    }
    
    private static func testDNSResolution() async -> [String: Bool] {
        let seeds = [
            "testnet-seed.dash.org",
            "testnet.dnsseed.dash.org",
            "seed.testnet.networks.dash.org"
        ]
        
        var results: [String: Bool] = [:]
        
        for seed in seeds {
            results[seed] = await ConnectionDiagnostics.canResolveHost(seed)
        }
        
        return results
    }
    
    private static func testInternetConnectivity() async -> Bool {
        // Test connection to a reliable public DNS server
        return await testTCPConnection(host: "8.8.8.8", port: 53, timeout: 3.0)
    }
    
    private static func checkConfiguration(_ config: SPVClientConfiguration) -> ConfigCheckResult {
        var result = ConfigCheckResult()
        
        result.network = config.network.name
        result.peerCount = config.additionalPeers.count
        result.maxPeers = Int(config.maxPeers)
        result.logLevel = config.logLevel
        result.dataDirectory = config.dataDirectory?.path
        
        // Validate peers
        for peer in config.additionalPeers {
            let validation = validatePeerAddress(peer, network: config.network)
            if !validation.isValid {
                result.issues.append(validation.issue!)
            }
        }
        
        // Check data directory
        if let dataDir = config.dataDirectory {
            result.dataDirectoryExists = FileManager.default.fileExists(atPath: dataDir.path)
            result.dataDirectoryWritable = FileManager.default.isWritableFile(atPath: dataDir.path)
            
            if !result.dataDirectoryExists {
                result.issues.append("Data directory does not exist")
            } else if !result.dataDirectoryWritable {
                result.issues.append("Data directory is not writable")
            }
        } else {
            result.issues.append("No data directory configured")
        }
        
        return result
    }
    
    private static func validatePeerAddress(_ peer: String, network: DashNetwork) -> (isValid: Bool, issue: String?) {
        let components = peer.split(separator: ":")
        
        guard components.count == 2 else {
            return (false, "Invalid peer format: \(peer)")
        }
        
        guard let port = Int(components[1]) else {
            return (false, "Invalid port in peer: \(peer)")
        }
        
        let expectedPort = network == .testnet ? 19999 : 9999
        if port != expectedPort {
            return (false, "Incorrect port \(port) for \(network.name), expected \(expectedPort)")
        }
        
        return (true, nil)
    }
    
    private static func testPeerConnectivity(_ client: SPVClient) async -> [PeerTestResult] {
        let peers = client.configuration.additionalPeers
        var results: [PeerTestResult] = []
        
        for peer in peers {
            var result = PeerTestResult(address: peer)
            let startTime = Date()
            
            let components = peer.split(separator: ":")
            guard components.count == 2,
                  let port = Int(components[1]) else {
                result.error = "Invalid peer format"
                results.append(result)
                continue
            }
            
            let host = String(components[0])
            
            // DNS resolution
            result.dnsResolvable = await ConnectionDiagnostics.canResolveHost(host)
            
            // TCP connectivity
            if result.dnsResolvable || isIPAddress(host) {
                result.tcpReachable = await testTCPConnection(host: host, port: port)
                if result.tcpReachable {
                    result.responseTime = Date().timeIntervalSince(startTime)
                    
                    // Try to get version/handshake info
                    result.dashNodeDetected = await testDashProtocol(host: host, port: port)
                }
            } else {
                result.error = "DNS resolution failed"
            }
            
            results.append(result)
            SyncDebugLogger.logPeerConnectivity([PeerConnectivityResult(
                address: peer,
                isReachable: result.tcpReachable,
                responseTime: result.responseTime,
                error: result.error
            )])
        }
        
        return results
    }
    
    private static func isIPAddress(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }
    
    private static func testDashProtocol(host: String, port: Int) async -> Bool {
        // This would require implementing Dash protocol handshake
        // For now, just return true if TCP is reachable
        return true
    }
    
    private static func testConnection(_ sdk: DashSDK) async -> ConnectionTestResult {
        var result = ConnectionTestResult()
        result.startTime = Date()
        
        // Check current state
        result.wasConnected = sdk.isConnected
        
        // Disconnect if connected
        if sdk.isConnected {
            print("Disconnecting existing connection...")
            try? await sdk.disconnect()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        }
        
        // Attempt connection
        do {
            print("Attempting to connect...")
            SyncDebugLogger.logStateChange("Starting connection test")
            
            try await sdk.connect()
            result.connectionSuccessful = true
            result.connectionTime = Date().timeIntervalSince(result.startTime)
            
            // Wait for peers
            var waitTime = 0
            while sdk.spvClient.peers == 0 && waitTime < 10 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                waitTime += 1
            }
            
            result.peersConnected = sdk.spvClient.peers
            result.currentHeight = sdk.spvClient.currentHeight
            
            SyncDebugLogger.logConnectionSuccess(
                peers: result.peersConnected,
                height: result.currentHeight
            )
            
        } catch {
            result.connectionSuccessful = false
            result.error = error.localizedDescription
            SyncDebugLogger.logConnectionError(error, context: "Connection test")
        }
        
        return result
    }
    
    private static func checkSyncStatus(_ client: SPVClient) -> SyncStatusResult {
        var result = SyncStatusResult()
        
        result.isSyncing = client.isSyncing
        result.currentHeight = client.currentHeight
        
        if let progress = client.syncProgress {
            result.syncProgress = progress.percentageComplete
            result.syncStatus = progress.status.rawValue
        }
        
        result.diagnostics = client.getSyncDiagnostics()
        
        return result
    }
    
    private static func checkCommonIssues(_ sdk: DashSDK) -> [String] {
        var issues: [String] = []
        
        // Simulator-specific issues
        #if targetEnvironment(simulator)
        issues.append("⚠️ Running on iOS Simulator - some network features may be limited")
        
        if sdk.spvClient.configuration.additionalPeers.contains(where: { 
            $0.contains("127.0.0.1") || $0.contains("localhost") 
        }) {
            issues.append("⚠️ Using localhost peers on simulator - ensure local node is accessible")
        }
        #endif
        
        // FFI issues
        if !FFIInitializer.initialized {
            issues.append("🔴 FFI not initialized - Core functionality will fail")
        }
        
        // Network issues
        if sdk.spvClient.configuration.additionalPeers.isEmpty {
            issues.append("⚠️ No peers configured - relying on DNS seeds only")
        }
        
        // Permission issues
        if let dataDir = sdk.spvClient.configuration.dataDirectory {
            if !FileManager.default.isWritableFile(atPath: dataDir.path) {
                issues.append("🔴 Data directory is not writable")
            }
        }
        
        return issues
    }
    
    // MARK: - Helper Methods
    
    private static func testTCPConnection(host: String, port: Int, timeout: TimeInterval = 5.0) async -> Bool {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "tcp.test.queue")
            var socketFD: Int32 = -1
            
            queue.async {
                // Create socket
                socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD != -1 else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer { close(socketFD) }
                
                // Set non-blocking
                fcntl(socketFD, F_SETFL, O_NONBLOCK)
                
                // Setup address
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(port).bigEndian
                
                // Convert host
                if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
                    // Try DNS resolution
                    guard let hostent = gethostbyname(host),
                          hostent.pointee.h_addrtype == AF_INET,
                          let addrList = hostent.pointee.h_addr_list,
                          let firstAddr = addrList.pointee else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    addr.sin_addr = firstAddr.withMemoryRebound(to: in_addr.self, capacity: 1) { $0.pointee }
                }
                
                // Connect
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
                
                // Wait for connection
                var writeSet = fd_set()
                __darwin_fd_zero(&writeSet)
                __darwin_fd_set(socketFD, &writeSet)
                
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                
                let selectResult = select(socketFD + 1, nil, &writeSet, nil, &tv)
                
                if selectResult > 0 && __darwin_fd_isset(socketFD, &writeSet) {
                    var error: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                    continuation.resume(returning: error == 0)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - Diagnostic Report Types

public struct ConnectionDiagnosticReport {
    var timestamp = Date()
    var ffiCheck = FFICheckResult()
    var networkCheck = NetworkCheckResult()
    var configCheck = ConfigCheckResult()
    var peerTests: [PeerTestResult] = []
    var connectionTest = ConnectionTestResult()
    var syncStatus = SyncStatusResult()
    var commonIssues: [String] = []
    var summary = ""
    
    mutating func generateSummary() {
        var sum = "\n📋 Diagnostic Summary:\n"
        
        // Overall status
        let overallOK = ffiCheck.initialized && 
                       networkCheck.isConnected && 
                       connectionTest.connectionSuccessful
        
        sum += overallOK ? "✅ Overall Status: READY\n" : "🔴 Overall Status: ISSUES DETECTED\n"
        
        // Key findings
        sum += "\nKey Findings:\n"
        
        if !ffiCheck.initialized {
            sum += "- 🔴 FFI not initialized\n"
        }
        if !ffiCheck.libraryLoaded {
            sum += "- 🔴 FFI library not loaded\n"
        }
        if !networkCheck.isConnected {
            sum += "- 🔴 No network connection\n"
        }
        if !connectionTest.connectionSuccessful {
            sum += "- 🔴 Failed to connect to Dash network\n"
        }
        if connectionTest.peersConnected == 0 {
            sum += "- ⚠️ No peers connected\n"
        }
        
        // Peer connectivity
        let reachablePeers = peerTests.filter { $0.tcpReachable }.count
        sum += "\n- Peer Connectivity: \(reachablePeers)/\(peerTests.count) reachable\n"
        
        // Common issues
        if !commonIssues.isEmpty {
            sum += "\nCommon Issues:\n"
            for issue in commonIssues {
                sum += "- \(issue)\n"
            }
        }
        
        summary = sum
    }
    
    func fullReport() -> String {
        var report = "=== DashPay Connection Diagnostic Report ===\n"
        report += "Generated: \(timestamp)\n\n"
        
        // FFI Check
        report += "1. FFI Status:\n"
        report += "   - Initialized: \(ffiCheck.initialized)\n"
        report += "   - Library Loaded: \(ffiCheck.libraryLoaded)\n"
        report += "   - Version: \(ffiCheck.version ?? "Unknown")\n"
        report += "   - Test Call: \(ffiCheck.testCallSuccessful ? "Success" : "Failed")\n"
        if let error = ffiCheck.lastError {
            report += "   - Last Error: \(error)\n"
        }
        
        // Network Check
        report += "\n2. Network Status:\n"
        report += "   - Connected: \(networkCheck.isConnected)\n"
        report += "   - Type: \(networkCheck.connectionType)\n"
        report += "   - Internet: \(networkCheck.internetReachable ? "Reachable" : "Unreachable")\n"
        
        // Add more sections...
        
        report += summary
        
        return report
    }
}

struct FFICheckResult {
    var initialized = false
    var libraryLoaded = false
    var version: String?
    var lastError: String?
    var testCallSuccessful = false
}

struct NetworkCheckResult {
    var isConnected = false
    var connectionType = "Unknown"
    var isExpensive = false
    var isConstrained = false
    var internetReachable = false
    var dnsResults: [String: Bool] = [:]
}

struct ConfigCheckResult {
    var network = ""
    var peerCount = 0
    var maxPeers = 0
    var logLevel = ""
    var dataDirectory: String?
    var dataDirectoryExists = false
    var dataDirectoryWritable = false
    var issues: [String] = []
}

struct PeerTestResult {
    var address = ""
    var dnsResolvable = false
    var tcpReachable = false
    var dashNodeDetected = false
    var responseTime: TimeInterval?
    var error: String?
}

struct ConnectionTestResult {
    var startTime = Date()
    var wasConnected = false
    var connectionSuccessful = false
    var connectionTime: TimeInterval = 0
    var peersConnected = 0
    var currentHeight: UInt32 = 0
    var error: String?
}

struct SyncStatusResult {
    var isSyncing = false
    var currentHeight: UInt32 = 0
    var syncProgress: Double = 0
    var syncStatus: String?
    var diagnostics = ""
}