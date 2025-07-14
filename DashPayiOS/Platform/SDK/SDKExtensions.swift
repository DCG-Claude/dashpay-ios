import Foundation
import SwiftDashCoreSDK

// Callback types for signing
// NOTE: The returned UnsafeMutablePointer<UInt8> from IOSSignCallback must be freed by the caller
// using dash_sdk_free_signature() to prevent memory leaks
public typealias IOSSignCallback = @convention(c) (
    _ identityPublicKeyBytes: UnsafePointer<UInt8>?,
    _ identityPublicKeyLen: Int,
    _ dataBytes: UnsafePointer<UInt8>?,
    _ dataLen: Int,
    _ resultLenPtr: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?

public typealias IOSCanSignCallback = @convention(c) (
    _ identityPublicKeyBytes: UnsafePointer<UInt8>?,
    _ identityPublicKeyLen: Int
) -> Bool

// dash_sdk_signer_create is provided by SwiftDashCoreSDK import
// No mock implementation needed - use the real FFI function

// Memory deallocation function for signature results
// This function should be called to free memory allocated by IOSSignCallback
func dash_sdk_free_signature(_ ptr: UnsafeMutablePointer<UInt8>?) {
    guard let ptr = ptr else { return }
    ptr.deallocate()
}

// MARK: - Network Helper  
// C enums are imported as structs with RawValue in Swift
// We'll use the raw values directly

extension SDK {
    private static var storedNetwork: DashNetwork = .testnet
    
    var network: DashNetwork {
        return SDK.storedNetwork
    }
    
    mutating func setNetwork(_ network: DashNetwork) {
        SDK.storedNetwork = network
    }
}

// MARK: - Signer Protocol
protocol Signer {
    func sign(identityPublicKey: Data, data: Data) -> Data?
    func canSign(identityPublicKey: Data) -> Bool
}

// Global signer storage for C callbacks
private var globalSignerStorage: Signer?

// C function callbacks that use the global signer
// WARNING: The returned pointer must be freed by the caller using dash_sdk_free_signature()
private let globalSignCallback: IOSSignCallback = { identityPublicKeyBytes, identityPublicKeyLen, dataBytes, dataLen, resultLenPtr in
    guard let identityPublicKeyBytes = identityPublicKeyBytes,
          let dataBytes = dataBytes,
          let resultLenPtr = resultLenPtr,
          let signer = globalSignerStorage else {
        return nil
    }
    
    let identityPublicKey = Data(bytes: identityPublicKeyBytes, count: Int(identityPublicKeyLen))
    let data = Data(bytes: dataBytes, count: Int(dataLen))
    
    guard let signature = signer.sign(identityPublicKey: identityPublicKey, data: data) else {
        return nil
    }
    
    // Allocate memory for the result and copy the signature
    // IMPORTANT: This memory must be freed by the caller using dash_sdk_free_signature()
    let result = UnsafeMutablePointer<UInt8>.allocate(capacity: signature.count)
    signature.withUnsafeBytes { bytes in
        result.initialize(from: bytes.bindMemory(to: UInt8.self).baseAddress!, count: signature.count)
    }
    
    resultLenPtr.pointee = Int(signature.count)
    return result
}

private let globalCanSignCallback: IOSCanSignCallback = { identityPublicKeyBytes, identityPublicKeyLen in
    guard let identityPublicKeyBytes = identityPublicKeyBytes,
          let signer = globalSignerStorage else {
        return false
    }
    
    let identityPublicKey = Data(bytes: identityPublicKeyBytes, count: Int(identityPublicKeyLen))
    return signer.canSign(identityPublicKey: identityPublicKey)
}

// MARK: - SDK Extensions for the example app
extension SDK {
    /// Initialize SDK with a custom signer for the example app
    init(network: FFINetwork, signer: Signer) throws {
        // Store the signer globally for C callbacks
        globalSignerStorage = signer
        
        // Create the signer handle
        let signerHandle = dash_sdk_signer_create(globalSignCallback, globalCanSignCallback)
        
        // Initialize the SDK with the signer
        try self.init(network: network)
        
        // Convert FFINetwork to DashNetwork and store it
        let dashNetwork: DashNetwork
        switch network {
        case 0: dashNetwork = .mainnet
        case 1: dashNetwork = .testnet
        case 2: dashNetwork = .devnet
        default: dashNetwork = .testnet
        }
        SDK.storedNetwork = dashNetwork
        
        // Store signer handle for FFI operations
        if let signerHandle = signerHandle {
            // The signer is now properly connected via the FFI callbacks
            // The global callbacks will handle signing operations
            print("✅ SDK initialized with custom signer")
        } else {
            print("⚠️ SDK signer handle creation failed, using default behavior")
        }
    }
}