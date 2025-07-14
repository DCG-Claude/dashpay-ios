import XCTest
@testable import DashPayiOS

/// Test to verify real FFI sync implementation works properly
class RealSyncProgressTest: XCTestCase {
    var sdk: DashSDK!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create testnet configuration with proper peers
        let config = SPVClientConfiguration.testnet()
        config.logLevel = "debug"  // Enable debug logging
        
        print("🧪 Test setup - Creating SDK with config: \(config.network.name)")
        sdk = try DashSDK(configuration: config)
    }
    
    override func tearDown() async throws {
        print("🧪 Test teardown - Disconnecting SDK")
        try? await sdk?.disconnect()
        sdk = nil
        try await super.tearDown()
    }
    
    func testRealSyncProgressStream() async throws {
        print("\n🧪 === Starting Real Sync Progress Test ===\n")
        
        // Connect to network
        print("🔗 Connecting to network...")
        try await sdk.connect()
        
        // Print diagnostics
        let diagnostics = sdk.spvClient.getSyncDiagnostics()
        print("📊 Initial Diagnostics:\n\(diagnostics)\n")
        
        // Test sync progress stream
        var progressUpdates: [DetailedSyncProgress] = []
        let progressExpectation = XCTestExpectation(description: "Receive real sync progress updates")
        let multipleUpdatesExpectation = XCTestExpectation(description: "Receive multiple progress updates")
        
        // Start collecting progress updates
        let syncTask = Task {
            print("🚀 Starting sync progress stream...")
            
            for await progress in sdk.syncProgressStream() {
                print("\n📊 Real Progress Update #\(progressUpdates.count + 1):")
                print("   🏷️  Stage: \(progress.stage.icon) \(progress.stage.description)")
                print("   📈 Percentage: \(progress.formattedPercentage)")
                print("   ⚡ Speed: \(progress.formattedSpeed)")
                print("   👥 Peers: \(progress.connectedPeers)")
                print("   📏 Height: \(progress.currentHeight)/\(progress.totalHeight)")
                print("   ⏱️  Time Remaining: \(progress.formattedTimeRemaining)")
                print("   💬 Message: \(progress.stageMessage)")
                print("   📊 Headers Processed: \(progress.totalHeadersProcessed)")
                
                progressUpdates.append(progress)
                
                // Fulfill expectation after getting first real update
                if progressUpdates.count == 1 && progress.percentage > 0 {
                    progressExpectation.fulfill()
                }
                
                // Fulfill multiple updates expectation
                if progressUpdates.count >= 3 {
                    multipleUpdatesExpectation.fulfill()
                }
                
                // Stop after getting enough updates or completion
                if progressUpdates.count >= 10 || progress.stage == .complete {
                    print("\n✅ Stopping sync stream after \(progressUpdates.count) updates")
                    break
                }
            }
        }
        
        // Wait for progress updates with reasonable timeout
        await fulfillment(of: [progressExpectation], timeout: 60.0)
        
        // Wait a bit more for multiple updates (optional)
        await fulfillment(of: [multipleUpdatesExpectation], timeout: 30.0, enforceOrder: false)
        
        // Cancel the sync task
        syncTask.cancel()
        
        // Print final diagnostics
        let finalDiagnostics = sdk.spvClient.getSyncDiagnostics()
        print("\n📊 Final Diagnostics:\n\(finalDiagnostics)\n")
        
        // Verify we got real progress updates
        XCTAssertFalse(progressUpdates.isEmpty, "Should have received progress updates")
        XCTAssertGreaterThan(progressUpdates.count, 1, "Should have received multiple progress updates")
        
        // Analyze progress updates
        if let firstProgress = progressUpdates.first {
            XCTAssertGreaterThan(firstProgress.totalHeight, 0, "Total height should be positive")
            XCTAssertGreaterThanOrEqual(firstProgress.connectedPeers, 0, "Should have peer count")
            XCTAssertFalse(firstProgress.stageMessage.isEmpty, "Should have stage message")
            XCTAssertNotEqual(firstProgress.stage, .failed, "Sync should not have failed")
        }
        
        // Check that we got different stages
        let stages = Set(progressUpdates.map { $0.stage })
        print("\n📊 Observed sync stages: \(stages.map { $0.description }.joined(separator: ", "))")
        XCTAssertGreaterThan(stages.count, 1, "Should have progressed through multiple stages")
        
        // Check that heights increased
        let heights = progressUpdates.map { $0.currentHeight }
        let uniqueHeights = Set(heights)
        print("📊 Unique heights observed: \(uniqueHeights.count)")
        XCTAssertGreaterThan(uniqueHeights.count, 1, "Should have seen height progress")
        
        print("\n✅ === Real Sync Progress Test Completed ===\n")
    }
    
    func testDirectFFISyncWithProgress() async throws {
        print("\n🧪 === Starting Direct FFI Sync Test ===\n")
        
        // Connect to network
        try await sdk.connect()
        
        // Get the SPV client directly
        let client = sdk.spvClient
        XCTAssertTrue(client.isConnected, "Client should be connected")
        
        let progressExpectation = XCTestExpectation(description: "FFI sync progress")
        var progressCount = 0
        var lastProgress: DetailedSyncProgress?
        
        // Use the public method
        try await client.syncToTipWithProgress(
            progressCallback: { progress in
                progressCount += 1
                lastProgress = progress
                
                print("\n🔄 FFI Progress #\(progressCount):")
                print("   Stage: \(progress.stage.description)")
                print("   Progress: \(progress.formattedPercentage)")
                print("   Height: \(progress.currentHeight)/\(progress.totalHeight)")
                print("   Speed: \(progress.formattedSpeed)")
                print("   Peers: \(progress.connectedPeers)")
                
                if progressCount >= 3 {
                    progressExpectation.fulfill()
                }
            },
            completionCallback: { success, error in
                print("\n✅ FFI Sync completed - Success: \(success), Error: \(error ?? "none")")
                if progressCount < 3 {
                    progressExpectation.fulfill()
                }
            }
        )
        
        // Wait for progress updates
        await fulfillment(of: [progressExpectation], timeout: 60.0)
        
        XCTAssertGreaterThan(progressCount, 0, "Should have received progress updates")
        XCTAssertNotNil(lastProgress, "Should have received at least one progress update")
        
        if let progress = lastProgress {
            XCTAssertGreaterThan(progress.totalHeight, 0, "Should have a valid total height")
            XCTAssertGreaterThanOrEqual(progress.percentage, 0, "Progress percentage should be valid")
            XCTAssertLessThanOrEqual(progress.percentage, 100, "Progress percentage should not exceed 100")
        }
        
        print("\n✅ === Direct FFI Sync Test Completed ===\n")
    }
}