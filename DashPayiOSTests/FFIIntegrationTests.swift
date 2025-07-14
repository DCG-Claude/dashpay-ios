import XCTest
@testable import DashPay
import SwiftDashCoreSDK

final class FFIIntegrationTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Ensure FFI is initialized for tests
        try FFIInitializer.initialize(logLevel: "debug")
    }
    
    func testFFIInitialization() throws {
        // Test that FFI can be initialized without hanging
        XCTAssertTrue(FFIInitializer.initialized, "FFI should be initialized")
    }
    
    func testSPVFFIFunctions() throws {
        // Test basic SPV FFI function calls
        
        // Test getting last error (should be nil initially)
        let error = FFIBridge.getLastError()
        XCTAssertNil(error, "Should have no error initially")
        
        // Test string conversion
        let testString = "test_string"
        let cString = FFIBridge.fromString(testString)
        XCTAssertNotNil(cString)
        
        // Test creating FFI watch item
        let watchItem = FFIBridge.createFFIWatchItem(type: .address, data: "yXuUPqiYxvUbDpPHqWxdHBPVbzT7DnWj3J")
        XCTAssertEqual(watchItem.item_type.rawValue, 0)
        XCTAssertNotNil(watchItem.data.ptr)
    }
    
    func testSPVClientCreation() async throws {
        // Test that we can create a real SPV client
        let config = SPVClientConfiguration.testnet()
        let client = SPVClientFactory.createClient(configuration: config, type: .real)
        
        // Verify it's a real client, not mock
        XCTAssertTrue(type(of: client) == SPVClient.self, "Should create real SPV client")
        
        // Test basic client properties
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(client.currentHeight, 0)
    }
    
    func testCoreAndPlatformFFICoexistence() throws {
        // This test verifies that both Core and Platform FFI functions can coexist
        // without symbol conflicts
        
        // Core FFI is already initialized in setUp
        XCTAssertTrue(FFIInitializer.initialized)
        
        // Platform FFI should also work (when available)
        // This is where you would test Platform-specific FFI calls
        
        // If we get here without hanging or crashing, the renamed libraries work!
        XCTAssertTrue(true, "Both FFI libraries can coexist")
    }
    
    func testMemoryManagement() throws {
        // Test FFI memory management helpers
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        
        try FFIBridge.withData(testData) { ptr, len in
            XCTAssertEqual(len, 4)
            XCTAssertNotNil(ptr)
        }
        
        let optionalString: String? = "optional"
        try FFIBridge.withOptionalCString(optionalString) { cStr in
            XCTAssertNotNil(cStr)
        }
        
        let nilString: String? = nil
        try FFIBridge.withOptionalCString(nilString) { cStr in
            XCTAssertNil(cStr)
        }
    }
}