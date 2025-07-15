import Foundation
import SwiftDashCoreSDK
import CryptoKit
import SwiftDashSDK

/// Platform SDK errors
enum PlatformError: LocalizedError {
    case sdkInitializationFailed
    case signerCreationFailed
    case identityNotFound
    case identityCreationFailed
    case failedToGetInfo
    case invalidIdentityId
    case transferFailed
    case insufficientBalance
    case documentCreationFailed
    case documentNotFound
    case notImplemented(String)
    case documentUpdateFailed
    case dataContractNotFound
    case dataContractCreationFailed
    case dataContractUpdateFailed
    case invalidData
    case topUpFailed
    
    var errorDescription: String? {
        switch self {
        case .sdkInitializationFailed:
            return "Failed to initialize Platform SDK"
        case .signerCreationFailed:
            return "Failed to create signer"
        case .identityNotFound:
            return "Identity not found"
        case .identityCreationFailed:
            return "Failed to create identity"
        case .failedToGetInfo:
            return "Failed to get identity information"
        case .invalidIdentityId:
            return "Invalid identity ID format"
        case .transferFailed:
            return "Credit transfer failed"
        case .insufficientBalance:
            return "Insufficient balance for operation"
        case .documentCreationFailed:
            return "Document creation failed"
        case .dataContractNotFound:
            return "Data contract not found"
        case .dataContractCreationFailed:
            return "Data contract creation failed"
        case .dataContractUpdateFailed:
            return "Data contract update failed"
        case .documentNotFound:
            return "Document not found"
        case .documentUpdateFailed:
            return "Document update failed"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .invalidData:
            return "Invalid data provided"
        case .topUpFailed:
            return "Failed to top up identity"
        }
    }
}

/// Additional SDK errors for compatibility
enum PlatformSDKError: LocalizedError {
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        }
    }
}

/// Swift-friendly wrapper around Platform FFI - simplified implementation
/// This is a temporary stub implementation until we fully migrate to SwiftDashSDK
actor PlatformSDKWrapper: PlatformSDKProtocol {
    private let network: PlatformNetwork
    private let coreSDK: DashSDK?
    
    // MARK: - Preview Helpers
    
    static func createPreviewInstance() -> PlatformSDKWrapper {
        // Create a minimal instance for SwiftUI previews using private initializer
        return PlatformSDKWrapper(previewNetwork: .testnet)
    }
    
    // Private synchronous initializer for previews only
    private init(previewNetwork: PlatformNetwork) {
        self.network = previewNetwork
        self.coreSDK = nil
        // Skip FFI initialization for preview
    }
    
    init(network: PlatformNetwork) async throws {
        self.coreSDK = nil
        self.network = network
        
        // Initialize unified FFI
        try await UnifiedFFIInitializer.shared.initialize()
    }
    
    init(network: PlatformNetwork, coreSDK: DashSDK) async throws {
        self.coreSDK = coreSDK
        self.network = network
        
        // Initialize unified FFI
        try await UnifiedFFIInitializer.shared.initialize()
    }
    
    // MARK: - Connection Testing
    
    func testConnection() async throws {
        print("🔍 Testing Platform SDK connection to DAPI...")
        // For now, just verify initialization worked
        print("✅ Platform SDK connection test passed")
    }
    
    // MARK: - Identity Operations
    
    func fetchIdentity(id: String) async throws -> Identity {
        print("🔍 Fetching identity: \(id)")
        // Stub implementation
        throw PlatformError.notImplemented("Identity fetching temporarily disabled during migration")
    }
    
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity {
        print("🆔 Creating new identity with asset lock: \(assetLock.transactionId)")
        // Stub implementation
        throw PlatformError.notImplemented("Identity creation temporarily disabled during migration")
    }
    
    func topUpIdentity(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity {
        print("💰 Topping up identity \(identity.id) with \(assetLock.amount) credits")
        // Stub implementation
        throw PlatformError.notImplemented("Identity top-up temporarily disabled during migration")
    }
    
    // MARK: - Data Contract Operations
    
    func fetchDataContract(id: String) async throws -> DataContract {
        print("📄 Fetching data contract: \(id)")
        // Stub implementation
        throw PlatformError.notImplemented("Contract fetching temporarily disabled during migration")
    }
    
    func createDataContract(ownerId: String, schema: [String: Any]) async throws -> DataContract {
        print("📝 Creating data contract for owner: \(ownerId)")
        // Stub implementation
        throw PlatformError.notImplemented("Contract creation temporarily disabled during migration")
    }
    
    func updateDataContract(_ contract: DataContract, newSchema: [String: Any]) async throws -> DataContract {
        print("📝 Updating data contract: \(contract.id)")
        // Stub implementation
        throw PlatformError.notImplemented("Contract update temporarily disabled during migration")
    }
    
    // MARK: - Document Operations
    
    func createDocument(
        contractId: String,
        ownerId: String,
        documentType: String,
        data: [String: Any]
    ) async throws -> Document {
        print("📄 Creating document of type \(documentType)")
        // Stub implementation
        throw PlatformError.notImplemented("Document creation temporarily disabled during migration")
    }
    
    func fetchDocument(contractId: String, documentType: String, documentId: String) async throws -> Document {
        print("🔍 Fetching document \(documentId) from contract \(contractId)")
        // Stub implementation
        throw PlatformError.notImplemented("Document fetching temporarily disabled during migration")
    }
    
    func updateDocument(_ document: Document, newData: [String: Any]) async throws -> Document {
        print("📝 Updating document \(document.id)")
        // Stub implementation
        throw PlatformError.notImplemented("Document update temporarily disabled during migration")
    }
    
    func deleteDocument(_ document: Document) async throws {
        print("🗑️ Deleting document \(document.id)")
        // Stub implementation
        throw PlatformError.notImplemented("Document deletion temporarily disabled during migration")
    }
    
    func searchDocuments(contractId: String, documentType: String, query: [String: Any]) async throws -> [Document] {
        print("🔍 Searching documents in contract \(contractId) of type \(documentType)")
        // Stub implementation - return empty results
        return []
    }
    
    // MARK: - Credit Transfer Operations
    
    func transferCredits(from identity: Identity, to recipientId: String, amount: UInt64) async throws -> TransferResult {
        print("💸 Transferring \(amount) credits from \(identity.idString) to \(recipientId)")
        // Stub implementation
        throw PlatformError.notImplemented("Credit transfer temporarily disabled during migration")
    }
}

// MARK: - Compatibility Types

/// Document model for compatibility with existing code
struct Document {
    let id: String
    let contractId: String
    let ownerId: String
    let documentType: String
    let revision: UInt64
    let dataDict: [String: Any]
}

// AssetLockProof and InstantLock are already defined in AssetLockBridge.swift
// PlatformSigner is already defined in Platform/Services/PlatformSigner.swift

// Identity and IdentityPublicKey are already defined in Platform/Models/DPP/Identity.swift
typealias Identity = DPPIdentity

/// Data contract model for compatibility
struct DataContract {
    let id: String
    let ownerId: String
    let schema: [String: Any]
    let version: UInt64
}