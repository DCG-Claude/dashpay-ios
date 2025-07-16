import XCTest
import SwiftData
@testable import DashPay

final class DatabaseValidationTests: XCTestCase {
    
    var container: ModelContainer!
    
    override func setUp() {
        super.setUp()
        // Clean up any existing test data
        ModelContainerHelper.cleanupCorruptStore()
    }
    
    override func tearDown() {
        container = nil
        super.tearDown()
    }
    
    // MARK: - Fresh Install Tests
    
    func testFreshInstallCreatesAllTables() throws {
        // Given: No existing database
        
        // When: Creating a new container
        container = try ModelContainerHelper.createContainer()
        
        // Then: All tables should be created
        let context = container.mainContext
        
        // Verify we can fetch from all tables without errors
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDWallet>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDAccount>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDWatchedAddress>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<Transaction>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<LocalUTXO>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<SyncState>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<Balance>()))
    }
    
    // MARK: - Migration Tests
    
    func testDatabaseValidation() throws {
        // Given: A container with proper schema
        container = try ModelContainerHelper.createContainer()
        
        // When: Validating the database
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
        
        // Then: Validation should pass
        XCTAssertTrue(validationResult.isValid, "Database validation should pass")
        XCTAssertTrue(validationResult.errors.isEmpty, "Should have no errors")
        XCTAssertFalse(validationResult.missingTables.contains("ZHDWATCHEDADDRESS"), 
                       "ZHDWATCHEDADDRESS table should exist")
    }
    
    // MARK: - Wallet Operations Tests
    
    func testCreateWalletWithAddresses() throws {
        // Given: A fresh container
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        // When: Creating a wallet with addresses
        let wallet = HDWallet(
            name: "Test Wallet",
            network: .testnet,
            encryptedSeed: Data(),
            seedHash: "test-hash"
        )
        
        let account = HDAccount(
            accountIndex: 0,
            label: "Main Account",
            extendedPublicKey: "xpub...",
            gapLimit: 20
        )
        
        let address = HDWatchedAddress(
            address: "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Receive Address"
        )
        
        context.insert(wallet)
        wallet.accounts.append(account)
        account.addresses.append(address)
        
        try context.save()
        
        // Then: Everything should be persisted correctly
        let fetchedWallets = try context.fetch(FetchDescriptor<HDWallet>())
        XCTAssertEqual(fetchedWallets.count, 1)
        XCTAssertEqual(fetchedWallets.first?.accounts.count, 1)
        XCTAssertEqual(fetchedWallets.first?.accounts.first?.addresses.count, 1)
        
        // Verify we can fetch HDWatchedAddress directly
        let fetchedAddresses = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertEqual(fetchedAddresses.count, 1)
        XCTAssertEqual(fetchedAddresses.first?.address, "yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
    }
    
    // MARK: - Sync Operations Tests
    
    func testSyncOperationsWithAddresses() throws {
        // Given: A wallet with addresses
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        let wallet = HDWallet(
            name: "Sync Test Wallet",
            network: .testnet,
            encryptedSeed: Data(),
            seedHash: "sync-test-hash"
        )
        
        let account = HDAccount(
            accountIndex: 0,
            label: "Sync Account",
            extendedPublicKey: "xpub...",
            gapLimit: 20
        )
        
        // Create multiple addresses
        for i in 0..<5 {
            let address = HDWatchedAddress(
                address: "y\(String(repeating: "X", count: 33 - String(i).count))\(i)",
                index: UInt32(i),
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/\(i)"
            )
            account.addresses.append(address)
        }
        
        context.insert(wallet)
        wallet.accounts.append(account)
        
        try context.save()
        
        // When: Simulating sync operations
        let syncState = SyncState(walletId: wallet.id)
        syncState.status = "syncing"
        syncState.currentHeight = 1000
        syncState.totalHeight = 2000
        syncState.progress = 0.5
        
        context.insert(syncState)
        try context.save()
        
        // Update address balances (simulating sync results)
        for address in account.addresses {
            let balance = LocalBalance(
                confirmed: 100_000_000, // 1 DASH
                pending: 0,
                instantLocked: 0,
                mempool: 0,
                mempoolInstant: 0,
                total: 100_000_000
            )
            address.balance = balance
        }
        
        try context.save()
        
        // Then: All sync data should be persisted
        let fetchedSyncState = try context.fetch(FetchDescriptor<SyncState>())
        XCTAssertEqual(fetchedSyncState.count, 1)
        XCTAssertEqual(fetchedSyncState.first?.progress, 0.5)
        
        // Verify address balances
        let fetchedAddresses = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        XCTAssertEqual(fetchedAddresses.count, 5)
        for address in fetchedAddresses {
            XCTAssertNotNil(address.balance)
            XCTAssertEqual(address.balance?.confirmed, 100_000_000)
        }
    }
    
    // MARK: - Error Recovery Tests
    
    func testRecoveryFromMissingTableError() throws {
        // This test simulates the recovery process
        // In a real scenario, we'd need to corrupt the database first
        
        // Given: Force cleanup to simulate missing tables
        ModelContainerHelper.cleanupCorruptStore()
        
        // When: Creating container (which should detect and recover)
        XCTAssertNoThrow(container = try ModelContainerHelper.createContainer())
        
        // Then: Container should be created successfully
        XCTAssertNotNil(container)
        
        // Verify all tables exist after recovery
        let context = container.mainContext
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDWatchedAddress>()))
    }
}

// MARK: - Performance Tests

extension DatabaseValidationTests {
    
    func testLargeScaleAddressCreationPerformance() throws {
        container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        measure {
            let wallet = HDWallet(
                name: "Performance Test Wallet",
                network: .testnet,
                encryptedSeed: Data(),
                seedHash: "perf-test-\(UUID().uuidString)"
            )
            
            let account = HDAccount(
                accountIndex: 0,
                label: "Performance Account",
                extendedPublicKey: "xpub...",
                gapLimit: 100
            )
            
            context.insert(wallet)
            wallet.accounts.append(account)
            
            // Create 100 addresses
            for i in 0..<100 {
                let address = HDWatchedAddress(
                    address: "y\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                    index: UInt32(i),
                    isChange: i % 2 == 0,
                    derivationPath: "m/44'/1'/0'/\(i % 2)/\(i)"
                )
                account.addresses.append(address)
            }
            
            do {
                try context.save()
            } catch {
                XCTFail("Failed to save: \(error)")
            }
        }
    }
}