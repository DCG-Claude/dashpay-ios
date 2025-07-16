import Foundation
import DashSPVFFI

/// Simple test to verify FFI is working
public class FFITest {
    
    public static func testFFI() {
        print("\n=== FFI Basic Test ===")
        
        // Test 1: Version
        print("1. Testing FFI version...")
        if let versionPtr = dash_spv_ffi_version() {
            let version = String(cString: versionPtr)
            print("✅ FFI Version: \(version)")
        } else {
            print("❌ Failed to get FFI version")
        }
        
        // Test 2: Clear error
        print("\n2. Testing error functions...")
        dash_spv_ffi_clear_error()
        print("✅ Error cleared")
        
        // Test 3: Init logging
        print("\n3. Testing logging initialization...")
        let result = "info".withCString { logLevel in
            dash_spv_ffi_init_logging(logLevel)
        }
        print("   Init logging result: \(result)")
        
        if result != 0 {
            if let errorPtr = dash_spv_ffi_get_last_error() {
                let error = String(cString: errorPtr)
                print("   Error: \(error)")
                dash_spv_ffi_clear_error()
            }
        }
        
        // Test 4: Create config
        print("\n4. Testing config creation...")
        
        // Try mainnet
        print("   Testing mainnet config...")
        if let config = dash_spv_ffi_config_mainnet() {
            print("✅ Mainnet config created: \(config)")
            dash_spv_ffi_config_destroy(config)
        } else {
            print("❌ Failed to create mainnet config")
        }
        
        // Try testnet
        print("   Testing testnet config...")
        if let config = dash_spv_ffi_config_testnet() {
            print("✅ Testnet config created: \(config)")
            dash_spv_ffi_config_destroy(config)
        } else {
            print("❌ Failed to create testnet config")
            if let errorPtr = dash_spv_ffi_get_last_error() {
                let error = String(cString: errorPtr)
                print("   Error: \(error)")
                dash_spv_ffi_clear_error()
            }
        }
        
        // Try with enum
        print("   Testing config_new with enum...")
        let testnetEnum = FFINetwork(rawValue: 1) // Testnet
        if let config = dash_spv_ffi_config_new(testnetEnum) {
            print("✅ Config created with enum: \(config)")
            dash_spv_ffi_config_destroy(config)
        } else {
            print("❌ Failed to create config with enum")
            if let errorPtr = dash_spv_ffi_get_last_error() {
                let error = String(cString: errorPtr)
                print("   Error: \(error)")
                dash_spv_ffi_clear_error()
            }
        }
        
        print("\n=== FFI Test Complete ===\n")
    }
}