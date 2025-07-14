import XCTest
@testable import DashPayiOS

/// Test suite for debugging sync connection issues
class SyncConnectionDebugTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear any previous debug logs
        SyncDebugLogger.clearLogFile()
    }
    
    /// Test comprehensive connection diagnostics
    func testConnectionDiagnostics() async throws {
        print("\n🧪 Running Connection Diagnostics Test\n")
        
        // Create SDK with testnet configuration
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        config.logLevel = "debug" // Enable debug logging
        
        // Add specific test peers if needed
        config.additionalPeers = [
            "35.165.67.85:19999",     // Known testnet peer
            "34.221.22.3:19999",      // Another testnet peer
            "52.42.181.201:19999"     // Additional testnet peer
        ]
        
        let sdk: DashSDK
        do {
            sdk = try await DashSDK(configuration: config)
            print("✅ SDK created successfully")
        } catch {
            print("🔴 Failed to create SDK: \(error)")
            throw error
        }
        
        // Run full diagnostics
        let report = await ConnectionDebugger.runFullDiagnostics(for: sdk)
        
        // Print summary
        print(report.summary)
        
        // Log to file
        if let logPath = SyncDebugLogger.getLogFilePath() {
            print("\n📄 Debug log saved to: \(logPath)")
        }
        
        // Assert basic requirements
        XCTAssertTrue(report.ffiCheck.initialized, "FFI should be initialized")
        XCTAssertTrue(report.networkCheck.isConnected, "Network should be connected")
        
        // If connection test failed, provide detailed info
        if !report.connectionTest.connectionSuccessful {
            print("\n🔴 Connection Test Failed:")
            print("Error: \(report.connectionTest.error ?? "Unknown")")
            print("Common issues found:")
            for issue in report.commonIssues {
                print("  - \(issue)")
            }
        }
    }
    
    /// Test enhanced connection with retry
    func testEnhancedConnectionWithRetry() async throws {
        print("\n🧪 Testing Enhanced Connection with Retry\n")
        
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        config.logLevel = "trace" // Maximum logging
        
        let sdk = try await DashSDK(configuration: config)
        
        // Add custom connection method with enhanced logging
        let client = sdk.spvClient
        
        do {
            try await connectWithEnhancedLogging(client: client)
            print("✅ Enhanced connection successful")
            
            // Verify connection
            XCTAssertTrue(client.isConnected, "Client should be connected")
            XCTAssertGreaterThan(client.peers, 0, "Should have at least one peer")
            
        } catch {
            print("🔴 Enhanced connection failed: \(error)")
            
            // Get state history for debugging
            print(SyncDebugLogger.getStateHistory())
            
            throw error
        }
    }
    
    /// Test peer connectivity independently
    func testPeerConnectivity() async throws {
        print("\n🧪 Testing Peer Connectivity\n")
        
        let testPeers = [
            "35.165.67.85:19999",
            "testnet-seed.dash.org:19999",
            "invalid.peer.address:12345"
        ]
        
        for peer in testPeers {
            print("\nTesting peer: \(peer)")
            
            let components = peer.split(separator: ":")
            guard components.count == 2,
                  let port = Int(components[1]) else {
                print("❌ Invalid peer format")
                continue
            }
            
            let host = String(components[0])
            
            // Test DNS
            let dnsResolvable = await ConnectionDiagnostics.canResolveHost(host)
            print("  DNS Resolution: \(dnsResolvable ? "✅" : "❌")")
            
            // Test TCP
            if dnsResolvable || isIPAddress(host) {
                let startTime = Date()
                let tcpReachable = await testTCPConnection(host: host, port: port)
                let responseTime = Date().timeIntervalSince(startTime)
                
                if tcpReachable {
                    print("  TCP Connection: ✅ (\(Int(responseTime * 1000))ms)")
                } else {
                    print("  TCP Connection: ❌")
                }
            }
        }
    }
    
    /// Test FFI initialization separately
    func testFFIInitialization() throws {
        print("\n🧪 Testing FFI Initialization\n")
        
        // Reset FFI state
        FFIInitializer.reset()
        
        // Test initialization
        do {
            try FFIInitializer.initializeWithRetry(logLevel: "debug", maxAttempts: 3)
            print("✅ FFI initialized successfully")
            
            // Verify initialization
            XCTAssertTrue(FFIInitializer.initialized, "FFI should be initialized")
            
            // Test FFI functionality
            if let version = dash_spv_ffi_version() {
                let versionStr = String(cString: version)
                print("✅ FFI Version: \(versionStr)")
                XCTAssertFalse(versionStr.isEmpty, "Version should not be empty")
            } else {
                XCTFail("FFI version should be available")
            }
            
        } catch {
            print("🔴 FFI initialization failed: \(error)")
            throw error
        }
    }
    
    /// Test sync progress monitoring
    func testSyncProgressMonitoring() async throws {
        print("\n🧪 Testing Sync Progress Monitoring\n")
        
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        let sdk = try await DashSDK(configuration: config)
        
        // Connect first
        try await sdk.connect()
        
        // Create expectation for sync progress
        let progressExpectation = expectation(description: "Sync progress received")
        progressExpectation.assertForOverFulfill = false
        
        var progressUpdates: [DetailedSyncProgress] = []
        
        // Start sync with progress monitoring
        Task {
            do {
                try await sdk.syncToTipWithProgress(
                    progressCallback: { progress in
                        print("📊 Progress: \(progress.formattedPercentage) - \(progress.stage.description)")
                        progressUpdates.append(progress)
                        
                        if progressUpdates.count >= 3 {
                            progressExpectation.fulfill()
                        }
                    },
                    completionCallback: { success, error in
                        if success {
                            print("✅ Sync completed")
                        } else {
                            print("🔴 Sync failed: \(error ?? "Unknown")")
                        }
                        progressExpectation.fulfill()
                    }
                )
            } catch {
                print("🔴 Sync error: \(error)")
                progressExpectation.fulfill()
            }
        }
        
        // Wait for progress updates
        await fulfillment(of: [progressExpectation], timeout: 30.0)
        
        // Verify we got progress updates
        XCTAssertGreaterThan(progressUpdates.count, 0, "Should have received progress updates")
        
        // Log progress history
        print("\n📈 Progress History:")
        for (index, progress) in progressUpdates.enumerated() {
            print("\(index + 1). \(progress.formattedPercentage) - \(progress.stage.description)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func connectWithEnhancedLogging(client: SPVClient) async throws {
        let maxRetries = 5
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                SyncDebugLogger.logConnectionAttempt(attempt, maxAttempts: maxRetries)
                SyncDebugLogger.logStateChange("Starting connection attempt \(attempt)")
                
                // Clear any FFI errors
                dash_spv_ffi_clear_error()
                
                // Try to connect
                try await client.connect()
                
                // Verify connection
                if client.isConnected {
                    SyncDebugLogger.logStateChange("Connected successfully")
                    
                    // Wait for peers
                    var peerWaitTime = 0
                    while client.peers == 0 && peerWaitTime < 20 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        peerWaitTime += 1
                        
                        if let progress = client.getCurrentSyncProgress() {
                            if progress.peerCount > 0 {
                                client.peers = Int(progress.peerCount)
                                break
                            }
                        }
                    }
                    
                    if client.peers > 0 {
                        SyncDebugLogger.logConnectionSuccess(
                            peers: client.peers,
                            height: client.currentHeight
                        )
                        return
                    } else {
                        throw DashSDKError.connectionFailed("Connected but no peers found")
                    }
                } else {
                    throw DashSDKError.connectionFailed("Connection reported as failed")
                }
                
            } catch {
                lastError = error
                SyncDebugLogger.logConnectionError(error, context: "Attempt \(attempt)")
                SyncDebugLogger.logStateChange("Connection failed: \(error)")
                
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt - 1))
                    print("⏳ Waiting \(delay)s before retry...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? DashSDKError.connectionFailed("Max retries exceeded")
    }
    
    private func isIPAddress(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }
    
    private func testTCPConnection(host: String, port: Int) async -> Bool {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "tcp.test")
            
            queue.async {
                var socketFD: Int32 = -1
                defer {
                    if socketFD >= 0 {
                        close(socketFD)
                    }
                }
                
                socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                fcntl(socketFD, F_SETFL, O_NONBLOCK)
                
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(port).bigEndian
                
                if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
                    guard let hostent = gethostbyname(host),
                          hostent.pointee.h_addrtype == AF_INET,
                          let addrList = hostent.pointee.h_addr_list,
                          let firstAddr = addrList.pointee else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    addr.sin_addr = firstAddr.withMemoryRebound(to: in_addr.self, capacity: 1) { $0.pointee }
                }
                
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
                
                var writeSet = fd_set()
                __darwin_fd_zero(&writeSet)
                __darwin_fd_set(socketFD, &writeSet)
                
                var tv = timeval(tv_sec: 5, tv_usec: 0)
                
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