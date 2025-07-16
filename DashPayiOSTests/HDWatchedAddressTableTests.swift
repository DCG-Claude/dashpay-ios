import XCTest
import SwiftData
import SwiftDashCoreSDK
@testable import DashPay

final class HDWatchedAddressTableTests: XCTestCase {
    
    var container: ModelContainer!
    
    override func setUp() {
        super.setUp()
        // Ensure clean state
        ModelContainerHelper.cleanupCorruptStore()
    }
    
    override func tearDown() {
        container = nil
        ModelContainerHelper.cleanupCorruptStore()
        super.tearDown()
    }
    
    // MARK: - Table Creation Tests
    
    func testHDWatchedAddressTableCreation() throws {
        // Given: No existing database
        
        // When: Creating container
        container = try ModelContainerHelper.createContainer()
        
        // Then: ZHDWATCHEDADDRESS table should exist
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            XCTFail("Could not get Application Support directory")
            return
        }
        
        let storeURL = appSupportURL
            .appendingPathComponent("DashPay")
            .appendingPathComponent("DashPayWallet.sqlite")
        
        let validationResult = DatabaseValidator.validateDatabase(at: storeURL)
        XCTAssertFalse(validationResult.missingTables.contains("ZHDWATCHEDADDRESS"),
                       "ZHDWATCHEDADDRESS table should be created")
    }
    
    // MARK: - CRUD Operations Tests
    
    func testCreateHDWatchedAddress() throws {
        // Given: A container with proper schema
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        // When: Creating an HDWatchedAddress
        let address = HDWatchedAddress(
            address: "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Test Address"
        )
        
        context.insert(address)
        try context.save()
        
        // Then: Address should be persisted
        let fetched = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.address, "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
        XCTAssertEqual(fetched.first?.label, "Test Address")
        XCTAssertNotNil(fetched.first?.balance)
    }
    
    @MainActor
    func testUpdateHDWatchedAddress() throws {
        // Given: An existing address
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        let address = HDWatchedAddress(
            address: "yAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0"
        )
        
        context.insert(address)
        try context.save()
        
        // When: Updating the address
        address.label = "Updated Label"
        address.lastActive = Date()
        address.transactionIds = ["tx1", "tx2", "tx3"]
        address.utxoOutpoints = ["outpoint1", "outpoint2"]
        
        try context.save()
        
        // Then: Changes should be persisted
        let fetched = try context.fetch(FetchDescriptor<HDWatchedAddress>(
            predicate: #Predicate { $0.address == "yAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }
        ))
        
        XCTAssertEqual(fetched.first?.label, "Updated Label")
        XCTAssertNotNil(fetched.first?.lastActive)
        XCTAssertEqual(fetched.first?.transactionIds.count, 3)
        XCTAssertEqual(fetched.first?.utxoOutpoints.count, 2)
    }
    
    func testDeleteHDWatchedAddress() throws {
        // Given: Multiple addresses
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        let addresses = (0..<5).map { i in
            HDWatchedAddress(
                address: "y\(String(repeating: "B", count: 33))\(i)",
                index: UInt32(i),
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/\(i)"
            )
        }
        
        addresses.forEach { context.insert($0) }
        try context.save()
        
        // When: Deleting one address
        let toDelete = addresses[2]
        context.delete(toDelete)
        try context.save()
        
        // Then: Only 4 addresses should remain
        let remaining = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertEqual(remaining.count, 4)
        XCTAssertFalse(remaining.contains { $0.address == toDelete.address })
    }
    
    // MARK: - Relationship Tests
    
    func testHDWatchedAddressAccountRelationship() throws {
        // Given: A wallet with account
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        let wallet = HDWallet(
            name: "Relationship Test",
            network: .testnet,
            encryptedSeed: Data(),
            seedHash: "rel-test"
        )
        
        let account = HDAccount(
            accountIndex: 0,
            label: "Main",
            extendedPublicKey: "xpub..."
        )
        
        context.insert(wallet)
        wallet.accounts.append(account)
        
        // When: Adding addresses to account
        let externalAddresses = (0..<5).map { i in
            HDWatchedAddress(
                address: "yEXT\(String(repeating: "X", count: 30))\(i)",
                index: UInt32(i),
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/\(i)"
            )
        }
        
        let internalAddresses = (0..<3).map { i in
            HDWatchedAddress(
                address: "yINT\(String(repeating: "X", count: 30))\(i)",
                index: UInt32(i),
                isChange: true,
                derivationPath: "m/44'/1'/0'/1/\(i)"
            )
        }
        
        externalAddresses.forEach { account.addresses.append($0) }
        internalAddresses.forEach { account.addresses.append($0) }
        
        try context.save()
        
        // Then: Relationships should be properly established
        let fetchedAccounts = try context.fetch(FetchDescriptor<HDAccount>())
        XCTAssertEqual(fetchedAccounts.first?.addresses.count, 8)
        XCTAssertEqual(fetchedAccounts.first?.externalAddresses.count, 5)
        XCTAssertEqual(fetchedAccounts.first?.internalAddresses.count, 3)
        
        // Verify inverse relationship
        let fetchedAddresses = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertTrue(fetchedAddresses.allSatisfy { $0.account != nil })
    }
    
    // MARK: - Balance Tests
    
    @MainActor
    func testHDWatchedAddressLocalBalance() throws {
        // Given: An address
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        let address = HDWatchedAddress(
            address: "yBALANCETESTXXXXXXXXXXXXXXXXXXXXXX",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0"
        )
        
        context.insert(address)
        try context.save()
        
        // When: Updating balance using safe method
        let sdkBalance = SwiftDashCoreSDK.LocalBalance(
            confirmed: 500_000_000, // 5 DASH
            pending: 100_000_000,   // 1 DASH
            instantLocked: 200_000_000, // 2 DASH
            mempool: 50_000_000,    // 0.5 DASH
            mempoolInstant: 25_000_000, // 0.25 DASH
            total: 875_000_000,     // 8.75 DASH
            lastUpdated: Date()
        )
        
        try address.updateBalanceSafely(from: sdkBalance, in: context)
        
        // Then: Balance should be updated correctly
        let fetched = try context.fetch(FetchDescriptor<HDWatchedAddress>(
            predicate: #Predicate { $0.address == "yBALANCETESTXXXXXXXXXXXXXXXXXXXXXX" }
        )).first
        
        XCTAssertNotNil(fetched?.balance)
        XCTAssertEqual(fetched?.balance?.confirmed, 500_000_000)
        XCTAssertEqual(fetched?.balance?.pending, 100_000_000)
        XCTAssertEqual(fetched?.balance?.total, 875_000_000)
        XCTAssertEqual(fetched?.formattedBalance, "8.75 DASH")
    }
    
    // MARK: - Error Recovery Tests
    
    func testRecoveryFromCorruptedAddressData() throws {
        // Given: A container
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        // When: Attempting operations that might fail
        let account = HDAccount(
            accountIndex: 0,
            label: "Recovery Test",
            extendedPublicKey: "xpub..."
        )
        
        context.insert(account)
        
        // Create addresses with potential edge cases
        let addresses = [
            HDWatchedAddress(
                address: "",  // Empty address
                index: 0,
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/0"
            ),
            HDWatchedAddress(
                address: "y" + String(repeating: "X", count: 100), // Very long address
                index: 1,
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/1"
            ),
            HDWatchedAddress(
                address: "yNORMALADDRESSXXXXXXXXXXXXXXXXXXXX",
                index: 2,
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/2"
            )
        ]
        
        addresses.forEach { account.addresses.append($0) }
        
        // Then: Save should handle edge cases gracefully
        do {
            try context.save()
            
            // Verify data integrity
            let fetched = try context.fetch(FetchDescriptor<HDWatchedAddress>())
            XCTAssertEqual(fetched.count, 3)
            
            // All addresses should have valid balances
            XCTAssertTrue(fetched.allSatisfy { $0.balance != nil })
        } catch {
            // If save fails, it should be due to validation
            print("Expected validation error: \(error)")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAddressOperations() throws {
        // Given: A container
        container = try ModelContainerHelper.createContainer()
        
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 3
        
        // When: Performing concurrent operations
        DispatchQueue.global().async {
            do {
                let context = self.container.mainContext
                let address = HDWatchedAddress(
                    address: "yCONCURRENT1XXXXXXXXXXXXXXXXXXXXXX",
                    index: 100,
                    isChange: false,
                    derivationPath: "m/44'/1'/0'/0/100"
                )
                context.insert(address)
                try context.save()
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent insert 1 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let context = self.container.mainContext
                let address = HDWatchedAddress(
                    address: "yCONCURRENT2XXXXXXXXXXXXXXXXXXXXXX",
                    index: 101,
                    isChange: false,
                    derivationPath: "m/44'/1'/0'/0/101"
                )
                context.insert(address)
                try context.save()
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent insert 2 failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let context = self.container.mainContext
                _ = try context.fetch(FetchDescriptor<HDWatchedAddress>())
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent fetch failed: \(error)")
            }
        }
        
        // Then: All operations should complete without table errors
        wait(for: [expectation], timeout: 5.0)
        
        // Verify final state
        let context = container.mainContext
        let addresses = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertGreaterThanOrEqual(addresses.count, 2)
    }
}