import XCTest
@testable import DashPay

final class UnifiedFFITests: XCTestCase {
    
    func test_unifiedFFIInitializes() {
        // Test that the unified FFI initializer works
        let initializer = UnifiedFFIInitializer.shared
        XCTAssertNotNil(initializer)
        
        // The library should initialize on first access
        XCTAssertTrue(UnifiedFFIInitializer.shared.isInitialized)
    }
    
    func test_dashUnifiedHeaderTypes() {
        // Test that we can access types from dash_unified_ffi.h
        let testNetwork = FFINetwork.testnet
        XCTAssertEqual(testNetwork.rawValue, 1)
    }
}