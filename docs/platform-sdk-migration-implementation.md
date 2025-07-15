# Platform SDK Migration: Implementation Guide

## Priority 1: Essential Features for MVP (Weeks 1-3)

### 1.1 Extend Official SDK with Identity Creation

**File**: `platform-ios/packages/swift-sdk/Sources/SwiftDashSDK/Identities+Creation.swift`

```swift
import Foundation
import CDashSDKFFI

public extension Identities {
    
    /// Create a new identity with asset lock funding
    func create(withAssetLock assetLock: AssetLockProof, signer: PlatformSigner) async throws -> Identity {
        guard let sdk = sdk, let handle = sdk.handle else {
            throw SDKError.invalidState("SDK not initialized")
        }
        
        // Step 1: Create identity
        let createResult = dash_sdk_identity_create(handle)
        
        if let error = createResult.error {
            defer { dash_sdk_error_free(createResult.error) }
            throw SDKError.fromDashSDKError(error.pointee)
        }
        
        guard let identityHandle = createResult.data else {
            throw SDKError.internalError("Failed to create identity")
        }
        
        defer { dash_sdk_identity_destroy(OpaquePointer(identityHandle)) }
        
        // Step 2: Fund with asset lock
        try await fund(identityHandle: OpaquePointer(identityHandle), 
                      assetLock: assetLock, 
                      signer: signer)
        
        // Step 3: Get identity info
        guard let info = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
            throw SDKError.internalError("Failed to get identity info")
        }
        
        defer { dash_sdk_identity_info_free(info) }
        
        let identityId = String(cString: info.pointee.id)
        let balance = info.pointee.balance
        
        return Identity(id: identityId, balance: balance)
    }
    
    private func fund(identityHandle: OpaquePointer, 
                     assetLock: AssetLockProof, 
                     signer: PlatformSigner) async throws {
        // Implementation similar to PlatformSDKWrapper.fundIdentityWithAssetLock
        // but adapted to official SDK patterns
    }
}
```

### 1.2 Add Signer Protocol

**File**: `platform-ios/packages/swift-sdk/Sources/SwiftDashSDK/Signer.swift`

```swift
import Foundation
import CDashSDKFFI

/// Protocol for signing Platform operations
public protocol PlatformSigner {
    /// Sign data with a specific identity key
    func sign(data: Data, forIdentityKey publicKey: Data) async throws -> Data
    
    /// Check if can sign for a specific key
    func canSign(forIdentityKey publicKey: Data) -> Bool
}

/// Bridge between Swift signer and C callbacks
class SignerBridge {
    private let signer: PlatformSigner
    private var handle: OpaquePointer?
    
    init(signer: PlatformSigner) {
        self.signer = signer
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        let signCallback: IOSSignCallback = { [weak self] pubKeyBytes, pubKeyLen, dataBytes, dataLen, resultLen in
            // Bridge async Swift to sync C callback
            // Use semaphore or cached signatures approach
        }
        
        let canSignCallback: IOSCanSignCallback = { [weak self] pubKeyBytes, pubKeyLen in
            guard let self = self,
                  let pubKeyBytes = pubKeyBytes else { return false }
            
            let publicKey = Data(bytes: pubKeyBytes, count: Int(pubKeyLen))
            return self.signer.canSign(forIdentityKey: publicKey)
        }
        
        handle = dash_sdk_signer_create(signCallback, canSignCallback)
    }
    
    deinit {
        if let handle = handle {
            dash_sdk_signer_destroy(handle)
        }
    }
}
```

### 1.3 Asset Lock Proof Support

**File**: `platform-ios/packages/swift-sdk/Sources/SwiftDashSDK/AssetLock.swift`

```swift
import Foundation

/// Asset lock proof for funding identities
public struct AssetLockProof {
    public let transaction: Transaction
    public let outputIndex: UInt32
    public let instantLock: InstantLock?
    
    public var amount: UInt64 {
        // Calculate from transaction output
        return transaction.outputs[Int(outputIndex)].amount
    }
    
    public init(transaction: Transaction, outputIndex: UInt32, instantLock: InstantLock? = nil) {
        self.transaction = transaction
        self.outputIndex = outputIndex
        self.instantLock = instantLock
    }
}

/// InstantLock proof
public struct InstantLock {
    public let txid: String
    public let signature: Data
    public let height: UInt32
    
    func encode() -> Data {
        // Encode for Platform consumption
        var data = Data()
        data.append(0x01) // version
        // Add encoded fields...
        return data
    }
}
```

## Priority 2: Core Platform Operations (Weeks 4-5)

### 2.1 Credit Transfer Implementation

**File**: `platform-ios/packages/swift-sdk/Sources/SwiftDashSDK/Identities+Transfer.swift`

```swift
public extension Identities {
    
    /// Transfer credits between identities
    func transferCredits(from fromId: String, 
                        to toId: String, 
                        amount: UInt64,
                        signer: PlatformSigner) async throws -> TransferResult {
        guard let sdk = sdk, let handle = sdk.handle else {
            throw SDKError.invalidState("SDK not initialized")
        }
        
        // Fetch source identity
        let fromResult = fromId.withCString { idCStr in
            dash_sdk_identity_fetch(handle, idCStr)
        }
        
        if let error = fromResult.error {
            defer { dash_sdk_error_free(fromResult.error) }
            throw SDKError.fromDashSDKError(error.pointee)
        }
        
        guard let fromHandle = fromResult.data else {
            throw SDKError.notFound("Source identity not found")
        }
        
        defer { dash_sdk_identity_destroy(OpaquePointer(fromHandle)) }
        
        // Create signer bridge
        let signerBridge = SignerBridge(signer: signer)
        
        // Perform transfer
        let transferResult = toId.withCString { toIdCStr in
            dash_sdk_identity_transfer_credits(
                handle,
                OpaquePointer(fromHandle),
                toIdCStr,
                amount,
                nil, // auto-select key
                signerBridge.handle,
                nil  // default settings
            )
        }
        
        if let error = transferResult.error {
            defer { dash_sdk_error_free(transferResult.error) }
            throw SDKError.fromDashSDKError(error.pointee)
        }
        
        // Parse result
        guard let resultData = transferResult.data else {
            throw SDKError.internalError("No transfer result")
        }
        
        let result = resultData.assumingMemoryBound(to: DashSDKTransferCreditsResult.self)
        defer { dash_sdk_transfer_credits_result_free(result) }
        
        return TransferResult(
            fromBalance: result.pointee.sender_balance,
            toBalance: result.pointee.receiver_balance
        )
    }
}
```

### 2.2 Document Operations

**File**: `platform-ios/packages/swift-sdk/Sources/SwiftDashSDK/Documents.swift`

```swift
import Foundation
import CDashSDKFFI

/// Document operations
public class Documents {
    private weak var sdk: SDK?
    
    init(sdk: SDK) {
        self.sdk = sdk
    }
    
    /// Create a new document
    public func create(contractId: String,
                      documentType: String,
                      ownerId: String,
                      data: [String: Any],
                      signer: PlatformSigner) async throws -> Document {
        guard let sdk = sdk, let handle = sdk.handle else {
            throw SDKError.invalidState("SDK not initialized")
        }
        
        // Convert data to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Implementation would follow PlatformSDKWrapper pattern
        // but adapted to official SDK structure
        
        throw SDKError.notImplemented("Document creation pending implementation")
    }
    
    /// Fetch document by ID
    public func get(contractId: String, 
                   documentType: String, 
                   documentId: String) async throws -> Document? {
        // Implementation
        throw SDKError.notImplemented("Document fetch pending implementation")
    }
}

// Add to SDK.swift
public extension SDK {
    /// Documents operations
    lazy var documents = Documents(sdk: self)
}
```

## Priority 3: Migration Adapter (Week 6)

### 3.1 Protocol Definition

**File**: `dashpay-ios/DashPayiOS/Shared/Bridges/PlatformSDKProtocol.swift`

```swift
import Foundation

/// Unified protocol for Platform SDK operations
protocol PlatformSDKProtocol {
    // Identity operations
    func fetchIdentity(id: String) async throws -> Identity
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity
    func transferCredits(from identity: Identity, to recipientId: String, amount: UInt64) async throws -> TransferResult
    func topUpIdentity(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity
    
    // Document operations
    func createDocument(contractId: String, ownerId: String, documentType: String, data: [String: Any]) async throws -> Document
    func fetchDocument(contractId: String, documentType: String, documentId: String) async throws -> Document
    func updateDocument(_ document: Document, newData: [String: Any]) async throws -> Document
    func deleteDocument(_ document: Document) async throws
    func searchDocuments(contractId: String, documentType: String, query: [String: Any]) async throws -> [Document]
    
    // Data contract operations
    func fetchDataContract(id: String) async throws -> DataContract
    func createDataContract(ownerId: String, schema: [String: Any]) async throws -> DataContract
    
    // Network operations
    func testConnection() async throws
    func getNetworkStatus() async -> PlatformNetworkStatus
}
```

### 3.2 Official SDK Adapter

**File**: `dashpay-ios/DashPayiOS/Shared/Bridges/OfficialSDKAdapter.swift`

```swift
import Foundation
import SwiftDashSDK // Official SDK module

/// Adapter to make official SDK conform to existing protocol
actor OfficialSDKAdapter: PlatformSDKProtocol {
    private let sdk: SwiftDashSDK.SDK
    private let signer: PlatformSignerAdapter
    private let network: PlatformNetwork
    
    init(network: PlatformNetwork, coreSDK: DashSDK?) async throws {
        self.network = network
        
        // Map network types
        let sdkNetwork: SwiftDashSDK.Network = switch network {
        case .mainnet: .mainnet
        case .testnet: .testnet  
        case .devnet: .devnet
        }
        
        // Initialize SDK
        self.sdk = try SwiftDashSDK.SDK(network: sdkNetwork)
        
        // Create signer adapter
        self.signer = PlatformSignerAdapter()
    }
    
    // MARK: - Identity Operations
    
    func fetchIdentity(id: String) async throws -> Identity {
        guard let sdkIdentity = try await sdk.identities.get(id: id) else {
            throw PlatformError.identityNotFound
        }
        
        // Convert SDK Identity to app Identity
        return Identity(
            id: sdkIdentity.id,
            balance: sdkIdentity.balance,
            revision: 0 // SDK doesn't expose revision yet
        )
    }
    
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity {
        // Convert app AssetLockProof to SDK type
        let sdkAssetLock = SwiftDashSDK.AssetLockProof(
            transaction: convertTransaction(assetLock.transaction),
            outputIndex: assetLock.outputIndex,
            instantLock: convertInstantLock(assetLock.instantLock)
        )
        
        let sdkIdentity = try await sdk.identities.create(
            withAssetLock: sdkAssetLock,
            signer: signer
        )
        
        return Identity(
            id: sdkIdentity.id,
            balance: sdkIdentity.balance,
            revision: 0
        )
    }
    
    // ... implement remaining protocol methods
}
```

## Priority 4: Testing Strategy (Weeks 7-8)

### 4.1 Unit Tests for SDK Extensions

**File**: `platform-ios/packages/swift-sdk/Tests/IdentityCreationTests.swift`

```swift
import XCTest
@testable import SwiftDashSDK

class IdentityCreationTests: XCTestCase {
    var sdk: SDK!
    
    override func setUp() async throws {
        SDK.initialize()
        sdk = try SDK(network: .testnet)
    }
    
    func testCreateIdentityWithAssetLock() async throws {
        // Create mock asset lock
        let assetLock = createMockAssetLock()
        let signer = MockSigner()
        
        // Create identity
        let identity = try await sdk.identities.create(
            withAssetLock: assetLock,
            signer: signer
        )
        
        XCTAssertFalse(identity.id.isEmpty)
        XCTAssertEqual(identity.balance, assetLock.amount)
    }
}
```

### 4.2 Integration Tests

**File**: `dashpay-ios/DashPayiOSTests/PlatformSDKMigrationTests.swift`

```swift
class PlatformSDKMigrationTests: XCTestCase {
    
    func testBehaviorParity() async throws {
        // Test with both implementations
        let customSDK = try PlatformSDKWrapper(network: .testnet)
        let officialSDK = try OfficialSDKAdapter(network: .testnet)
        
        // Create identical asset locks
        let assetLock = createTestAssetLock()
        
        // Create identities with both
        let customIdentity = try await customSDK.createIdentity(with: assetLock)
        let officialIdentity = try await officialSDK.createIdentity(with: assetLock)
        
        // Verify similar behavior
        XCTAssertEqual(customIdentity.balance, officialIdentity.balance)
    }
}
```

## Priority 5: Rollout Plan (Weeks 9-10)

### 5.1 Feature Flag Implementation

**File**: `dashpay-ios/DashPayiOS/Core/Configuration/FeatureFlags.swift`

```swift
struct FeatureFlags {
    
    /// Percentage of users to enable official SDK for
    static var officialSDKRolloutPercentage: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "OfficialSDKRollout") 
        #else
        return RemoteConfig.shared.value(for: "official_sdk_rollout") ?? 0
        #endif
    }
    
    /// Check if official SDK should be used for current user
    static func shouldUseOfficialSDK(userId: String) -> Bool {
        let hash = abs(userId.hashValue)
        let bucket = hash % 100
        return bucket < officialSDKRolloutPercentage
    }
}
```

### 5.2 Metrics Collection

**File**: `dashpay-ios/DashPayiOS/Core/Analytics/PlatformSDKMetrics.swift`

```swift
class PlatformSDKMetrics {
    
    enum SDKVersion: String {
        case custom = "custom_wrapper"
        case official = "official_sdk"
    }
    
    static func trackOperation(
        _ operation: String,
        sdk: SDKVersion,
        success: Bool,
        duration: TimeInterval,
        error: Error? = nil
    ) {
        var properties: [String: Any] = [
            "operation": operation,
            "sdk_version": sdk.rawValue,
            "success": success,
            "duration_ms": Int(duration * 1000)
        ]
        
        if let error = error {
            properties["error_type"] = String(describing: type(of: error))
            properties["error_message"] = error.localizedDescription
        }
        
        Analytics.shared.track("platform_sdk_operation", properties: properties)
    }
    
    static func trackMigrationEvent(_ event: String, properties: [String: Any] = [:]) {
        var props = properties
        props["event"] = event
        Analytics.shared.track("platform_sdk_migration", properties: props)
    }
}
```

## Implementation Timeline

| Week | Focus | Deliverables |
|------|-------|--------------|
| 1-2 | SDK Extension Setup | Fork repo, development environment, basic structure |
| 3 | Identity Operations | Creation, funding, balance queries |
| 4 | Credit Transfers | Transfer implementation with signer |
| 5 | Document Operations | Basic CRUD operations |
| 6 | Adapter Layer | Protocol definition, adapter implementation |
| 7 | Unit Testing | SDK extension tests |
| 8 | Integration Testing | Parity tests, performance benchmarks |
| 9 | Feature Flags | Rollout infrastructure |
| 10 | Initial Rollout | 10% of users, monitoring |

## Success Metrics

1. **Operation Success Rate**: >= 99.5% (same as current)
2. **Performance**: P95 latency within 10% of current
3. **Crash Rate**: No increase from baseline
4. **Code Coverage**: >= 80% for new SDK code
5. **User Feedback**: No increase in Platform-related issues

## Risk Mitigation

1. **Rollback Plan**: Feature flag allows instant rollback
2. **Monitoring**: Real-time dashboards for all metrics
3. **Gradual Rollout**: 10% → 50% → 100% over 2 weeks
4. **A/B Testing**: Compare metrics between implementations
5. **Backup Implementation**: Keep wrapper for 30 days post-migration