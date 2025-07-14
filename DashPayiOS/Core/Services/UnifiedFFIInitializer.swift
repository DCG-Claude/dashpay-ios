import Foundation
import SwiftDashCoreSDK

/// Manages unified FFI library initialization and callback registration
final class UnifiedFFIInitializer {
    static let shared = UnifiedFFIInitializer()
    private var isInitialized = false
    private var coreSDKHandle: OpaquePointer?
    
    private init() {}
    
    /// Initialize the unified FFI library
    func initialize() {
        guard !isInitialized else { return }
        
        // Initialize unified library
        let result = dash_unified_init()
        if result == 0 {
            isInitialized = true
            print("✅ Unified FFI library initialized successfully")
        } else {
            print("❌ Failed to initialize unified FFI library: \(result)")
        }
    }
    
    /// Register Core SDK handle for Platform SDK callbacks
    func registerCoreSDK(_ handle: OpaquePointer) {
        guard isInitialized else {
            print("⚠️ Cannot register Core SDK - unified library not initialized")
            return
        }
        
        self.coreSDKHandle = handle
        let result = dash_unified_register_core_sdk_handle(UnsafeMutableRawPointer(handle))
        if result == 0 {
            print("✅ Core SDK registered with unified library")
        } else {
            print("❌ Failed to register Core SDK: \(result)")
        }
    }
}