import XCTest
@testable import DashPay
import SwiftDashCoreSDK

final class AssetLockBridgeTests: XCTestCase {
    var bridge: AssetLockBridge!
    var mockCoreSDK: MockDashSDK!
    var mockPlatformSDK: MockPlatformSDK!
    
    override func setUp() async throws {
        mockCoreSDK = MockDashSDK()
        mockPlatformSDK = MockPlatformSDK()
        bridge = await AssetLockBridge(coreSDK: mockCoreSDK, platformSDK: mockPlatformSDK)
    }
    
    func test_fundIdentity_createsAssetLockTransaction() async throws {
        // Given
        let wallet = Wallet(id: "test_wallet", balance: 1_000_000_000, address: "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX") // 10 DASH
        let amount: UInt64 = 100_000_000 // 1 DASH
        let expectedTxId = "mock_tx_id_12345"
        
        // Mock SDK will return a test transaction
        
        // When
        let assetLock = try await bridge.fundIdentity(
            from: wallet,
            amount: amount
        )
        
        // Then
        XCTAssertNotNil(assetLock.transactionId)
        XCTAssertEqual(assetLock.amount, amount)
    }
    
    func test_fundIdentity_insufficientBalance_throwsError() async throws {
        // Given
        let wallet = Wallet(id: "test_wallet", balance: 50_000_000, address: "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX") // 0.5 DASH
        let amount: UInt64 = 100_000_000 // 1 DASH
        
        // Simulate insufficient balance by having the bridge check fail
        // Since wallet balance < amount + fee
        
        // When/Then
        do {
            _ = try await bridge.fundIdentity(from: wallet, amount: amount)
            XCTFail("Expected error to be thrown")
        } catch AssetLockError.insufficientBalance {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func test_generateAssetLockProof_createsValidProof() async throws {
        // Given
        let transaction = SwiftDashCoreSDK.Transaction(
            txid: "test_tx",
            height: nil,
            timestamp: Date(),
            amount: 100_000_000,
            fee: 1000,
            confirmations: 0,
            isInstantLocked: false,
            raw: Data(),
            size: 250,
            version: 2
        )
        
        // When
        let instantLock = InstantLock(txid: transaction.txid, height: 1000, signature: Data())
        let proof = try await bridge.generateAssetLockProof(
            for: transaction,
            outputIndex: 0,
            instantLock: instantLock
        )
        
        // Then
        XCTAssertEqual(proof.transaction.txid, transaction.txid)
        XCTAssertEqual(proof.outputIndex, 0)
        XCTAssertNotNil(proof.instantLock)
    }
}

// Mock objects for testing

class MockPlatformSDK: PlatformSDKProtocol {
    func fetchIdentity(id: String) async throws -> Identity {
        return Identity(id: id, balance: 1000000, revision: 1)
    }
    
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity {
        return Identity(id: "mock_identity_id", balance: assetLock.amount, revision: 1)
    }
    
    func topUpIdentity(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity {
        return Identity(id: identity.id, balance: identity.balance + assetLock.amount, revision: identity.revision + 1)
    }
    
    func transferCredits(from identity: Identity, to recipientId: String, amount: UInt64) async throws -> TransferResult {
        return TransferResult(fromId: identity.id, toId: recipientId, amount: amount)
    }
    
    func fetchDataContract(id: String) async throws -> DataContract {
        return DataContract(id: id, ownerId: "mock_owner", schema: [:], version: 1, revision: 1)
    }
    
    func createDataContract(ownerId: String, schema: [String: Any]) async throws -> DataContract {
        return DataContract(id: "mock_contract_id", ownerId: ownerId, schema: schema, version: 1, revision: 1)
    }
    
    func updateDataContract(_ contract: DataContract, newSchema: [String: Any]) async throws -> DataContract {
        return DataContract(id: contract.id, ownerId: contract.ownerId, schema: newSchema, version: contract.version + 1, revision: contract.revision + 1)
    }
    
    func createDocument(contractId: String, ownerId: String, documentType: String, data: [String: Any]) async throws -> Document {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return Document(id: "mock_doc_id", contractId: contractId, ownerId: ownerId, documentType: documentType, revision: 1, data: jsonData)
    }
    
    func fetchDocument(contractId: String, documentType: String, documentId: String) async throws -> Document {
        let emptyData = try JSONSerialization.data(withJSONObject: [:])
        return Document(id: documentId, contractId: contractId, ownerId: "mock_owner", documentType: documentType, revision: 1, data: emptyData)
    }
    
    func updateDocument(_ document: Document, newData: [String: Any]) async throws -> Document {
        let jsonData = try JSONSerialization.data(withJSONObject: newData)
        return Document(id: document.id, contractId: document.contractId, ownerId: document.ownerId, documentType: document.documentType, revision: document.revision + 1, data: jsonData)
    }
    
    func deleteDocument(_ document: Document) async throws {
        // Mock delete - no-op
    }
    
    func searchDocuments(contractId: String, documentType: String, query: [String: Any]) async throws -> [Document] {
        return []
    }
}

struct MockWallet {
    let id = "mock_wallet"
    let balance: UInt64
    let address = "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}

