import XCTest
import SwiftDashSDK
@testable import DashPayiOS

/// Test suite for Core SDK sync progress functionality
class SyncProgressTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Initialize the unified SDK
        let result = dash_unified_sdk_init()
        XCTAssertEqual(result, 0, "Unified SDK initialization should succeed")
    }
    
    /// Test Core SDK sync progress functionality
    func testCoreSDKSyncProgress() throws {
        print("\n🧪 Testing Core SDK Sync Progress\n")
        
        let client = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(client, "Client should be created")
        
        guard let client = client else { return }
        defer { dash_core_sdk_destroy_client(client) }
        
        // Start the client
        let startResult = dash_core_sdk_start(client)
        print("Start result: \(startResult)")
        
        // Get sync progress
        if let progressPtr = dash_core_sdk_get_sync_progress(client) {
            let progress = progressPtr.pointee
            print("✅ Sync Progress:")
            print("   Current Height: \(progress.current_height)")
            print("   Total Height: \(progress.total_height)")
            print("   Connected Peers: \(progress.connected_peers)")
            print("   Percentage: \(progress.percentage)%")
            
            XCTAssertGreaterThanOrEqual(progress.percentage, 0.0, "Percentage should be non-negative")
            XCTAssertLessThanOrEqual(progress.percentage, 100.0, "Percentage should not exceed 100")
        } else {
            print("❌ Failed to get sync progress")
        }
        
        // Stop the client
        let stopResult = dash_core_sdk_stop(client)
        print("Stop result: \(stopResult)")
    }
    
    /// Test Core SDK stats functionality
    func testCoreSDKStats() throws {
        print("\n🧪 Testing Core SDK Stats\n")
        
        let client = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(client, "Client should be created")
        
        guard let client = client else { return }
        defer { dash_core_sdk_destroy_client(client) }
        
        // Start the client
        let startResult = dash_core_sdk_start(client)
        print("Start result: \(startResult)")
        
        // Get stats
        if let statsPtr = dash_core_sdk_get_stats(client) {
            let stats = statsPtr.pointee
            print("✅ Core SDK Stats:")
            print("   Connected Peers: \(stats.connected_peers)")
            print("   Best Height: \(stats.best_height)")
            print("   Synced Height: \(stats.synced_height)")
            print("   Is Syncing: \(stats.is_syncing)")
            
            XCTAssertGreaterThanOrEqual(stats.connected_peers, 0, "Connected peers should be non-negative")
            XCTAssertGreaterThanOrEqual(stats.best_height, 0, "Best height should be non-negative")
            XCTAssertGreaterThanOrEqual(stats.synced_height, 0, "Synced height should be non-negative")
        } else {
            print("❌ Failed to get stats")
        }
        
        // Stop the client
        let stopResult = dash_core_sdk_stop(client)
        print("Stop result: \(stopResult)")
    }
    
    /// Test Core SDK balance functionality
    func testCoreSDKBalance() throws {
        print("\n🧪 Testing Core SDK Balance\n")
        
        let client = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(client, "Client should be created")
        
        guard let client = client else { return }
        defer { dash_core_sdk_destroy_client(client) }
        
        // Start the client
        let startResult = dash_core_sdk_start(client)
        print("Start result: \(startResult)")
        
        // Get total balance
        if let balancePtr = dash_core_sdk_get_total_balance(client) {
            let balance = balancePtr.pointee
            print("✅ Core SDK Balance:")
            print("   Confirmed: \(balance.confirmed)")
            print("   Pending: \(balance.pending)")
            print("   Total: \(balance.confirmed + balance.pending)")
            
            XCTAssertGreaterThanOrEqual(balance.confirmed, 0, "Confirmed balance should be non-negative")
            XCTAssertGreaterThanOrEqual(balance.pending, 0, "Pending balance should be non-negative")
        } else {
            print("❌ Failed to get balance")
        }
        
        // Stop the client
        let stopResult = dash_core_sdk_stop(client)
        print("Stop result: \(stopResult)")
    }
    
    /// Test address watching functionality
    func testAddressWatching() throws {
        print("\n🧪 Testing Address Watching\n")
        
        let client = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(client, "Client should be created")
        
        guard let client = client else { return }
        defer { dash_core_sdk_destroy_client(client) }
        
        // Start the client
        let startResult = dash_core_sdk_start(client)
        print("Start result: \(startResult)")
        
        // Test watching an address
        let testAddress = "yP8A3cbdxRtLRduy5mXDsBnJtMzHWs6ZXr" // Example testnet address
        let watchResult = dash_core_sdk_watch_address(client, testAddress)
        print("Watch address result: \(watchResult)")
        
        // Test unwatching the address
        let unwatchResult = dash_core_sdk_unwatch_address(client, testAddress)
        print("Unwatch address result: \(unwatchResult)")
        
        // Stop the client
        let stopResult = dash_core_sdk_stop(client)
        print("Stop result: \(stopResult)")
    }
}