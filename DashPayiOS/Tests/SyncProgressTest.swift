import XCTest
@testable import DashPayiOS

class SyncProgressTest: XCTestCase {
    var sdk: DashSDK!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create testnet configuration with fallback peers
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        sdk = try DashSDK(configuration: config)
    }
    
    override func tearDown() async throws {
        try? await sdk?.disconnect()
        sdk = nil
        try await super.tearDown()
    }
    
    func testSyncProgressStream() async throws {
        // Connect to network
        try await sdk.connect()
        
        // Test sync progress stream
        var progressUpdates: [DetailedSyncProgress] = []
        let expectation = XCTestExpectation(description: "Sync progress updates")
        
        // Start collecting progress updates
        Task {
            for await progress in sdk.syncProgressStream() {
                print("📊 Progress Update:")
                print("   Stage: \(progress.stage.description)")
                print("   Percentage: \(progress.formattedPercentage)")
                print("   Speed: \(progress.formattedSpeed)")
                print("   Peers: \(progress.connectedPeers)")
                print("   Current Height: \(progress.currentHeight)")
                print("   Total Height: \(progress.totalHeight)")
                
                progressUpdates.append(progress)
                
                // Fulfill expectation after getting at least one real update
                if progressUpdates.count >= 1 && progress.percentage > 0 {
                    expectation.fulfill()
                    break
                }
                
                // Stop after complete
                if progress.stage == .complete {
                    break
                }
            }
        }
        
        // Wait for progress updates
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify we got real progress updates
        XCTAssertFalse(progressUpdates.isEmpty, "Should have received progress updates")
        
        if let firstProgress = progressUpdates.first {
            XCTAssertGreaterThan(firstProgress.totalHeight, 0, "Total height should be positive")
            XCTAssertGreaterThanOrEqual(firstProgress.connectedPeers, 0, "Should have peer count")
            XCTAssertFalse(firstProgress.stageMessage.isEmpty, "Should have stage message")
        }
    }
    
    func testFFISyncWithProgress() async throws {
        // Connect to network
        try await sdk.connect()
        
        // Get the SPV client directly
        let client = sdk.client
        guard client.isConnected, let ffiClient = client.ffiClient else {
            XCTFail("Client not connected")
            return
        }
        
        let progressExpectation = XCTestExpectation(description: "FFI sync progress")
        let completionExpectation = XCTestExpectation(description: "FFI sync completion")
        
        var progressCount = 0
        
        // Create callback holder
        let callbackHolder = DetailedCallbackHolder(
            progressCallback: { progress in
                if let detailedProgress = progress as? DetailedSyncProgress {
                    progressCount += 1
                    print("🔄 FFI Progress #\(progressCount):")
                    print("   Stage: \(detailedProgress.stage)")
                    print("   Progress: \(detailedProgress.formattedPercentage)")
                    print("   Height: \(detailedProgress.currentHeight)/\(detailedProgress.totalHeight)")
                    
                    if progressCount >= 1 {
                        progressExpectation.fulfill()
                    }
                }
            },
            completionCallback: { success, error in
                print("✅ FFI Sync completed - Success: \(success), Error: \(error ?? "none")")
                completionExpectation.fulfill()
            }
        )
        
        let userData = Unmanaged.passRetained(callbackHolder).toOpaque()
        
        // Start sync with FFI
        let result = dash_spv_ffi_client_sync_to_tip_with_progress(
            ffiClient,
            detailedSyncProgressCallback,
            detailedSyncCompletionCallback,
            userData
        )
        
        if result != 0 {
            Unmanaged<DetailedCallbackHolder>.fromOpaque(userData).release()
            XCTFail("Failed to start FFI sync: \(FFIBridge.getLastError() ?? "Unknown error")")
            return
        }
        
        // Wait for at least one progress update
        await fulfillment(of: [progressExpectation], timeout: 30.0)
        
        XCTAssertGreaterThan(progressCount, 0, "Should have received progress updates")
    }
}

// MARK: - Helper Classes (copied from SPVClient for testing)

private class DetailedCallbackHolder {
    let progressCallback: (@Sendable (Any) -> Void)?
    let completionCallback: (@Sendable (Bool, String?) -> Void)?
    
    init(progressCallback: (@Sendable (Any) -> Void)? = nil,
         completionCallback: (@Sendable (Bool, String?) -> Void)? = nil) {
        self.progressCallback = progressCallback
        self.completionCallback = completionCallback
    }
}

// Callback functions for FFI
private let detailedSyncProgressCallback: @convention(c) (UnsafePointer<FFIDetailedSyncProgress>?, UnsafeMutableRawPointer?) -> Void = { ffiProgress, userData in
    guard let userData = userData,
          let ffiProgress = ffiProgress else { return }
    
    let holder = Unmanaged<DetailedCallbackHolder>.fromOpaque(userData).takeUnretainedValue()
    
    // Convert FFI progress to Swift DetailedSyncProgress
    let progress = ffiProgress.pointee
    let stage: SyncStage = {
        switch progress.stage {
        case .Connecting: return .connecting
        case .QueryingHeight: return .queryingHeight
        case .Downloading: return .downloading
        case .Validating: return .validating
        case .Storing: return .storing
        case .Complete: return .complete
        case .Failed: return .failed
        default: return .downloading
        }
    }()
    
    let stageMessage = String(cString: progress.stage_message.ptr)
    
    let detailedProgress = DetailedSyncProgress(
        currentHeight: progress.current_height,
        totalHeight: progress.total_height,
        percentage: progress.percentage,
        headersPerSecond: progress.headers_per_second,
        estimatedSecondsRemaining: progress.estimated_seconds_remaining,
        stage: stage,
        stageMessage: stageMessage,
        connectedPeers: progress.connected_peers,
        totalHeadersProcessed: progress.total_headers,
        syncStartTimestamp: Date(timeIntervalSince1970: TimeInterval(progress.sync_start_timestamp))
    )
    
    holder.progressCallback?(detailedProgress)
}

private let detailedSyncCompletionCallback: @convention(c) (Bool, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { success, error, userData in
    guard let userData = userData else { return }
    let holder = Unmanaged<DetailedCallbackHolder>.fromOpaque(userData).takeUnretainedValue()
    let err = error.map { String(cString: $0) }
    holder.completionCallback?(success, err)
    // Release the holder after completion
    Unmanaged<DetailedCallbackHolder>.fromOpaque(userData).release()
}