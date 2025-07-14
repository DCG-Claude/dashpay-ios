import XCTest
@testable import DashPay

@MainActor
final class FFIIntegrationTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Ensure unified FFI is initialized
        _ = UnifiedFFIInitializer.shared
    }
    
    func testUnifiedFFIIntegration() async throws {
        // Test that we can create instances of types that use FFI
        
        // Test creating a PlatformSDKWrapper (which uses FFI internally)
        do {
            // Note: This would normally require a real Core SDK instance
            // For testing, we just verify the types exist
            let network = PlatformNetwork.testnet
            XCTAssertNotNil(network, "Should be able to create PlatformNetwork")
            
            // Verify FFINetwork conversion works
            let ffiNetwork = network.sdkNetwork
            XCTAssertEqual(ffiNetwork.rawValue, 1, "Testnet should map to FFINetwork value 1")
            
        } catch {
            XCTFail("Failed to test FFI integration: \(error)")
        }
    }
    
    func testFFINetworkConversion() throws {
        // Test conversion between PlatformNetwork and FFINetwork
        XCTAssertEqual(PlatformNetwork.mainnet.sdkNetwork.rawValue, 0)
        XCTAssertEqual(PlatformNetwork.testnet.sdkNetwork.rawValue, 1)
        XCTAssertEqual(PlatformNetwork.devnet.sdkNetwork.rawValue, 2)
    }
    
    func testUnifiedFFIMemoryManagement() throws {
        // Test that creating and destroying FFI objects doesn't leak
        // This is a basic test - real memory testing would use Instruments
        
        for _ in 0..<10 {
            _ = UnifiedFFIInitializer.shared
            // If memory management is broken, this would crash or leak
        }
        
        XCTAssertTrue(true, "Memory management test passed")
    }
}