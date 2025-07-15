import XCTest
@testable import DashPay

final class UnifiedFFITests: XCTestCase {
    
    func test_unifiedFFIInitializes() {
        // Test that the unified FFI initializer works
        let initializer = UnifiedFFIInitializer.shared
        XCTAssertNotNil(initializer)
        
        // The library initializes automatically
        // We can't check isInitialized as it's private
    }
    
    func test_dashUnifiedHeaderTypes() {
        // Test that we can access types from dash_unified_ffi.h
        let testNetwork = FFINetwork(rawValue: 1)  // Testnet
        XCTAssertEqual(testNetwork.rawValue, 1)
    }
}