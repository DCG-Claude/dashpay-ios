import XCTest
import SwiftDashSDK
@testable import DashPayiOS

/// Test suite for debugging sync connection issues
class SyncConnectionDebugTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Initialize the unified SDK
        let result = dash_unified_sdk_init()
        XCTAssertEqual(result, 0, "Unified SDK initialization should succeed")
    }
    
    /// Test Core SDK version availability
    func testCoreSDKVersion() throws {
        print("\n🧪 Testing Core SDK Version\n")
        
        if let version = dash_core_sdk_version() {
            let versionStr = String(cString: version)
            print("✅ Core SDK Version: \(versionStr)")
            XCTAssertFalse(versionStr.isEmpty, "Version should not be empty")
        } else {
            XCTFail("Core SDK version should be available")
        }
    }
    
    /// Test Core SDK client creation
    func testCoreSDKClientCreation() throws {
        print("\n🧪 Testing Core SDK Client Creation\n")
        
        // Test testnet client creation
        let testnetClient = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(testnetClient, "Testnet client should be created")
        
        if let client = testnetClient {
            print("✅ Testnet client created successfully")
            
            // Test client lifecycle
            let startResult = dash_core_sdk_start(client)
            print("Start result: \(startResult)")
            
            let stopResult = dash_core_sdk_stop(client)
            print("Stop result: \(stopResult)")
            
            // Clean up
            dash_core_sdk_destroy_client(client)
            print("✅ Client destroyed successfully")
        }
    }
    
    /// Test Core SDK sync functionality
    func testCoreSDKSync() throws {
        print("\n🧪 Testing Core SDK Sync\n")
        
        let client = dash_core_sdk_create_client_testnet()
        XCTAssertNotNil(client, "Client should be created")
        
        guard let client = client else { return }
        defer { dash_core_sdk_destroy_client(client) }
        
        // Start the client
        let startResult = dash_core_sdk_start(client)
        print("Start result: \(startResult)")
        
        // Test sync to tip
        let syncResult = dash_core_sdk_sync_to_tip(client)
        print("Sync result: \(syncResult)")
        
        // Test getting block height
        var height: UInt32 = 0
        let heightResult = dash_core_sdk_get_block_height(client, &height)
        if heightResult == 0 {
            print("✅ Block height: \(height)")
        } else {
            print("❌ Failed to get block height: \(heightResult)")
        }
        
        // Stop the client
        let stopResult = dash_core_sdk_stop(client)
        print("Stop result: \(stopResult)")
    }
    
    /// Test Unified SDK functionality
    func testUnifiedSDK() throws {
        print("\n🧪 Testing Unified SDK\n")
        
        // Test SDK version
        if let version = dash_unified_sdk_version() {
            let versionStr = String(cString: version)
            print("✅ Unified SDK Version: \(versionStr)")
            XCTAssertFalse(versionStr.isEmpty, "Version should not be empty")
        }
        
        // Test core support availability
        let hasCoreSupport = dash_unified_sdk_has_core_support()
        print("Core support available: \(hasCoreSupport)")
        XCTAssertTrue(hasCoreSupport, "Core support should be available")
        
        // Test core SDK availability
        let coreEnabled = dash_core_sdk_is_enabled()
        print("Core SDK enabled: \(coreEnabled)")
        XCTAssertTrue(coreEnabled, "Core SDK should be enabled")
    }
    
    /// Test Platform SDK version
    func testPlatformSDKVersion() throws {
        print("\n🧪 Testing Platform SDK Version\n")
        
        // Test SDK initialization
        dash_sdk_init()
        
        // Test platform SDK version
        if let version = dash_sdk_version() {
            let versionStr = String(cString: version)
            print("✅ Platform SDK Version: \(versionStr)")
            XCTAssertFalse(versionStr.isEmpty, "Version should not be empty")
        } else {
            XCTFail("Platform SDK version should be available")
        }
    }
    
}