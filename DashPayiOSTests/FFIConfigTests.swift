import XCTest
@testable import DashPay
import SwiftDashCoreSDK

final class FFIConfigTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Reset FFI state for clean testing
        FFIInitializer.reset()
    }
    
    func testFFIInitialization() throws {
        // Test basic FFI initialization
        XCTAssertFalse(FFIInitializer.initialized, "FFI should not be initialized at start")
        
        try FFIInitializer.initialize(logLevel: "debug")
        
        XCTAssertTrue(FFIInitializer.initialized, "FFI should be initialized after call")
    }
    
    func testFFIConfigCreationDirect() throws {
        // Ensure FFI is initialized
        if !FFIInitializer.initialized {
            try FFIInitializer.initialize(logLevel: "debug")
        }
        
        // Clear any existing errors
        dash_spv_ffi_clear_error()
        
        // Test creating config for each network type directly
        let networks: [(name: String, value: UInt32)] = [
            ("mainnet", 0),
            ("testnet", 1),
            ("regtest", 2),
            ("devnet", 3)
        ]
        
        for (name, rawValue) in networks {
            print("Testing network: \(name) with value: \(rawValue)")
            
            // Create FFINetwork from raw value
            guard let ffiNetwork = FFINetwork(rawValue: rawValue) else {
                XCTFail("Failed to create FFINetwork for \(name)")
                continue
            }
            
            // Try to create config
            let config = dash_spv_ffi_config_new(ffiNetwork)
            
            if config == nil {
                // Get error message
                var errorMsg = "No error message"
                if let error = dash_spv_ffi_get_last_error() {
                    errorMsg = String(cString: error)
                    dash_spv_ffi_clear_error()
                }
                XCTFail("Failed to create config for \(name): \(errorMsg)")
            } else {
                XCTAssertNotNil(config, "Config should be created for \(name)")
                dash_spv_ffi_config_destroy(config)
            }
        }
    }
    
    func testSPVClientConfigurationFFIConfig() throws {
        // Test the full configuration flow
        let config = SPVClientConfiguration.testnet()
        
        do {
            let ffiConfig = try config.createFFIConfig()
            XCTAssertNotNil(ffiConfig, "FFI config should be created")
            
            // Clean up - cast back to proper type
            let configPtr = OpaquePointer(ffiConfig)
            dash_spv_ffi_config_destroy(configPtr)
        } catch {
            XCTFail("Failed to create FFI config: \(error)")
        }
    }
    
    func testNetworkEnumMapping() {
        // Test that our Swift enum maps correctly to FFI enum
        XCTAssertEqual(DashNetwork.mainnet.ffiValue.rawValue, 0)
        XCTAssertEqual(DashNetwork.testnet.ffiValue.rawValue, 1)
        XCTAssertEqual(DashNetwork.regtest.ffiValue.rawValue, 2)
        XCTAssertEqual(DashNetwork.devnet.ffiValue.rawValue, 3)
    }
    
    func testDiagnostics() {
        // Run full diagnostics
        let report = FFIDiagnostics.runDiagnostics()
        print("=== FFI DIAGNOSTICS REPORT ===")
        print(report)
        print("==============================")
        
        // The test passes if diagnostics run without crashing
        XCTAssertTrue(report.contains("FFI Diagnostic Report"))
    }
}