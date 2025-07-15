import XCTest
@testable import DashPay
import SwiftDashCoreSDK

/// Simple test to verify unified FFI integration is working
final class SimpleIntegrationTest: XCTestCase {
    
    func testUnifiedFFIInitialization() throws {
        // Test that unified FFI initializer exists and works
        let initializer = UnifiedFFIInitializer.shared
        XCTAssertNotNil(initializer, "Unified FFI initializer should exist")
        
        // Initialize the unified library
        initializer.initialize()
        
        // If we get here without crashes, the unified FFI is working
        XCTAssertTrue(true, "Unified FFI initialization completed without crashes")
    }
    
    func testPlatformNetworkMapping() throws {
        // Test network mapping which was a key issue during integration
        XCTAssertEqual(PlatformNetwork.mainnet.sdkNetwork.rawValue, 0)
        XCTAssertEqual(PlatformNetwork.testnet.sdkNetwork.rawValue, 1)
        XCTAssertEqual(PlatformNetwork.devnet.sdkNetwork.rawValue, 2)
    }
    
    func testFFITypeAvailability() throws {
        // Test that FFI types are available through bridging header
        // These would fail to compile if the header search paths weren't working
        let _ = FFINetwork(rawValue: 0) // Dash/Mainnet
        let _ = FFINetwork(rawValue: 1) // Testnet  
        let _ = FFINetwork(rawValue: 2) // Regtest
        let _ = FFINetwork(rawValue: 3) // Devnet
        
        XCTAssertTrue(true, "FFI types are accessible")
    }
}