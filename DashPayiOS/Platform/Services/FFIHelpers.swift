import Foundation
import SwiftDashSDK

/// Platform FFI specific errors
enum PlatformFFIError: LocalizedError {
    case initializationFailed(String)
    case invalidData
    case timeout
    case handleValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "FFI initialization failed: \(message)"
        case .invalidData:
            return "Invalid data returned from FFI"
        case .timeout:
            return "FFI operation timed out"
        case .handleValidationFailed:
            return "FFI handle validation failed"
        }
    }
}

/// Enhanced FFI utilities for safer Platform SDK integration
class FFIHelpers {
    
    // MARK: - Safe FFI Result Handling
    
    /// Safely handle FFI results with proper error extraction and cleanup
    static func handleResult<T>(_ result: DashSDKResult, transform: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        // Check for errors first
        if let error = result.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown FFI error"
            defer { dash_sdk_error_free(error) }
            throw PlatformFFIError.initializationFailed(errorMessage)
        }
        
        // Ensure we have valid data
        guard let data = result.data else {
            throw PlatformFFIError.invalidData
        }
        
        // Transform the data
        return try transform(data)
    }
    
    /// Safely handle FFI results that return handles
    static func handleHandleResult(_ result: DashSDKResult) throws -> OpaquePointer {
        return try handleResult(result) { data in
            return OpaquePointer(data)
        }
    }
    
    /// Safely handle FFI results that return simple data
    static func handleDataResult(_ result: DashSDKResult) throws -> Data {
        return try handleResult(result) { data in
            // This would need to be implemented based on the specific FFI function
            // For now, return empty data
            return Data()
        }
    }
    
    // MARK: - Error Message Extraction
    
    /// Extract error message from FFI error with null safety
    static func extractErrorMessage(_ error: UnsafeMutablePointer<DashSDKError>) -> String {
        guard let messagePtr = error.pointee.message else {
            return "Unknown FFI error (null message)"
        }
        
        return String(cString: messagePtr)
    }
    
    // MARK: - Memory Management Helpers
    
    /// Safely execute a block with automatic cleanup of an identity handle
    static func withIdentityHandle<T>(
        _ handle: OpaquePointer,
        execute: (OpaquePointer) throws -> T
    ) rethrows -> T {
        defer {
            dash_sdk_identity_destroy(handle)
        }
        return try execute(handle)
    }
    
    /// Safely execute a block with automatic cleanup of a contract handle
    static func withContractHandle<T>(
        _ handle: OpaquePointer,
        execute: (OpaquePointer) throws -> T
    ) rethrows -> T {
        defer {
            dash_sdk_data_contract_destroy(handle)
        }
        return try execute(handle)
    }
    
    /// Safely execute a block with automatic cleanup of a document handle
    static func withDocumentHandle<T>(
        _ handle: OpaquePointer,
        execute: (OpaquePointer) throws -> T
    ) rethrows -> T {
        defer {
            dash_sdk_document_handle_destroy(handle)
        }
        return try execute(handle)
    }
    
    // MARK: - String Conversion Helpers
    
    /// Safely convert C string to Swift String with null checks
    static func safeString(from cString: UnsafePointer<CChar>?) -> String? {
        guard let cString = cString else {
            return nil
        }
        return String(cString: cString)
    }
    
    /// Execute block with C string and automatic cleanup
    static func withCString<T>(_ string: String, execute: (UnsafePointer<CChar>) throws -> T) rethrows -> T {
        return try string.withCString(execute)
    }
    
    // MARK: - Async FFI Wrappers
    
    /// Wrapper for async FFI calls with timeout
    static func asyncFFICall<T>(
        timeout: TimeInterval = 30.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                return try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw PlatformFFIError.timeout
            }
            
            // Return the first completed task and cancel others
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Validation Helpers
    
    /// Validate handle is not null
    static func validateHandle(_ handle: OpaquePointer?, operation: String) throws {
        guard handle != nil else {
            throw PlatformFFIError.handleValidationFailed
        }
    }
    
    /// Validate data pointer is not null
    static func validateData(_ data: UnsafeMutableRawPointer?, operation: String) throws {
        guard data != nil else {
            throw PlatformFFIError.handleValidationFailed
        }
    }
}

// MARK: - FFI Resource Manager

/// Manages FFI resources with automatic cleanup
class FFIResourceManager {
    private var identityHandles: Set<OpaquePointer> = []
    private var contractHandles: Set<OpaquePointer> = []
    private var documentHandles: Set<OpaquePointer> = []
    private var signerHandles: Set<OpaquePointer> = []
    
    deinit {
        cleanup()
    }
    
    /// Register an identity handle for cleanup
    func register(identityHandle: OpaquePointer) {
        identityHandles.insert(identityHandle)
    }
    
    /// Register a contract handle for cleanup
    func register(contractHandle: OpaquePointer) {
        contractHandles.insert(contractHandle)
    }
    
    /// Register a document handle for cleanup
    func register(documentHandle: OpaquePointer) {
        documentHandles.insert(documentHandle)
    }
    
    /// Register a signer handle for cleanup
    func register(signerHandle: OpaquePointer) {
        signerHandles.insert(signerHandle)
    }
    
    /// Manually cleanup a specific handle
    func cleanup(identityHandle: OpaquePointer) {
        if identityHandles.contains(identityHandle) {
            dash_sdk_identity_destroy(identityHandle)
            identityHandles.remove(identityHandle)
        }
    }
    
    /// Cleanup all resources
    func cleanup() {
        // Clean up identity handles
        for handle in identityHandles {
            dash_sdk_identity_destroy(handle)
        }
        identityHandles.removeAll()
        
        // Clean up contract handles
        for handle in contractHandles {
            dash_sdk_data_contract_destroy(handle)
        }
        contractHandles.removeAll()
        
        // Clean up document handles
        for handle in documentHandles {
            dash_sdk_document_handle_destroy(handle)
        }
        documentHandles.removeAll()
        
        // Clean up signer handles
        for handle in signerHandles {
            dash_sdk_signer_destroy(handle)
        }
        signerHandles.removeAll()
    }
}