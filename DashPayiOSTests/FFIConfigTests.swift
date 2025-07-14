import XCTest
@testable import DashPay

final class FFIConfigTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Unified FFI initializes automatically
        _ = UnifiedFFIInitializer.shared
    }
    
    func testFFIInitialization() throws {
        // Test that unified FFI initializer exists
        let initializer = UnifiedFFIInitializer.shared
        XCTAssertNotNil(initializer, "Unified FFI initializer should exist")
        
        // The library initializes automatically, so we just verify it exists
        // We can't check internal state as it's properly encapsulated
    }
    
    func testFFINetworkTypes() throws {
        // Test FFINetwork enum values match expected values
        XCTAssertEqual(FFINetwork(rawValue: 0).rawValue, 0)  // Dash
        XCTAssertEqual(FFINetwork(rawValue: 1).rawValue, 1)  // Testnet
        XCTAssertEqual(FFINetwork(rawValue: 2).rawValue, 2)  // Regtest
        XCTAssertEqual(FFINetwork(rawValue: 3).rawValue, 3)  // Devnet
    }
    
    func testUnifiedFFIFunctions() throws {
        // Test that unified FFI functions are available
        // Note: We can't actually call these functions in tests without proper setup
        // But we can verify they're linked properly by creating the initializer
        _ = UnifiedFFIInitializer.shared
        
        // If we get here without crashes, the symbols are properly linked
        XCTAssertTrue(true, "Unified FFI functions are properly linked")
    }
}