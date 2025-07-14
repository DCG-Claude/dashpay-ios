import Foundation
import SwiftDashCoreSDK

/// UnifiedFFI specific errors
enum UnifiedFFIError: LocalizedError {
    case notInitialized
    case registrationFailed(Int32)
    case initializationFailed(Int32)
    case invalidHandle
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Unified FFI library not initialized"
        case .registrationFailed(let code):
            return "Failed to register Core SDK: \(code)"
        case .initializationFailed(let code):
            return "Failed to initialize unified FFI library: \(code)"
        case .invalidHandle:
            return "Invalid handle provided"
        }
    }
}

/// Manages unified FFI library initialization and callback registration
final class UnifiedFFIInitializer {
    static let shared = UnifiedFFIInitializer()
    private var isInitialized = false
    private var coreSDKHandle: OpaquePointer?
    
    private init() {}
    
    /// Initialize the unified FFI library
    func initialize() throws {
        guard !isInitialized else { return }
        
        // Initialize unified library
        let result = dash_unified_init()
        if result == 0 {
            isInitialized = true
            print("✅ Unified FFI library initialized successfully")
        } else {
            throw UnifiedFFIError.initializationFailed(result)
        }
    }
    
    /// Register Core SDK handle for Platform SDK callbacks
    func registerCoreSDK(_ handle: OpaquePointer?) throws {
        guard isInitialized else {
            throw UnifiedFFIError.notInitialized
        }
        
        guard let handle = handle else {
            throw UnifiedFFIError.invalidHandle
        }
        
        self.coreSDKHandle = handle
        let result = dash_unified_register_core_sdk_handle(UnsafeMutableRawPointer(handle))
        if result == 0 {
            print("✅ Core SDK registered with unified library")
        } else {
            throw UnifiedFFIError.registrationFailed(result)
        }
    }
}