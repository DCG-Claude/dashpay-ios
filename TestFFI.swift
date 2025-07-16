import Foundation
import DashSPVFFI

func testFFIFunctions() {
    print("\n=== Testing FFI Functions ===")
    
    // Test 1: Initialize logging
    print("\n1. Testing dash_spv_ffi_init_logging...")
    let logResult = dash_spv_ffi_init_logging("debug")
    print("   Result: \(logResult)")
    
    // Test 2: Create config
    print("\n2. Testing config creation...")
    if let config = dash_spv_ffi_config_new(1) { // 1 = testnet
        print("   ✅ Config created successfully")
        
        // Test 3: Add peer
        print("\n3. Testing add peer...")
        let peerResult = dash_spv_ffi_config_add_peer(config, "127.0.0.1:19999")
        print("   Add peer result: \(peerResult)")
        
        // Test 4: Create client
        print("\n4. Testing client creation...")
        if let client = dash_spv_ffi_client_new(config) {
            print("   ✅ Client created successfully")
            
            // Test 5: Start client
            print("\n5. Testing client start...")
            let startResult = dash_spv_ffi_client_start(client)
            print("   Start result: \(startResult)")
            
            if startResult != 0 {
                // Get error
                if let errorMsg = dash_spv_ffi_get_last_error() {
                    let error = String(cString: errorMsg)
                    print("   ❌ Error: \(error)")
                    dash_spv_ffi_clear_error()
                }
            }
            
            // Clean up
            dash_spv_ffi_client_destroy(client)
        } else {
            print("   ❌ Failed to create client")
            if let errorMsg = dash_spv_ffi_get_last_error() {
                let error = String(cString: errorMsg)
                print("   Error: \(error)")
                dash_spv_ffi_clear_error()
            }
        }
        
        dash_spv_ffi_config_destroy(config)
    } else {
        print("   ❌ Failed to create config")
        if let errorMsg = dash_spv_ffi_get_last_error() {
            let error = String(cString: errorMsg)
            print("   Error: \(error)")
            dash_spv_ffi_clear_error()
        }
    }
    
    print("\n=== FFI Test Complete ===\n")
}

// Run the test
testFFIFunctions()