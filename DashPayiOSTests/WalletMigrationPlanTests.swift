import XCTest
import SwiftData
@testable import DashPay

@MainActor
final class WalletMigrationPlanTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clean up before each test
        ModelContainerHelper.cleanupCorruptStore()
    }
    
    override func tearDown() {
        // Clean up after each test
        ModelContainerHelper.cleanupCorruptStore()
        super.tearDown()
    }
    
    // MARK: - Schema Version Tests
    
    func testWalletSchemaV1Contains_AllRequiredModels() {
        // Given: WalletSchemaV1
        let models = WalletSchemaV1.models
        
        // Then: Should contain all wallet-related models
        XCTAssertEqual(models.count, 7)
        
        let modelTypes = models.map { String(describing: $0) }
        XCTAssertTrue(modelTypes.contains("HDWallet"))
        XCTAssertTrue(modelTypes.contains("HDAccount"))
        XCTAssertTrue(modelTypes.contains("HDWatchedAddress"))
        XCTAssertTrue(modelTypes.contains("Transaction"))
        XCTAssertTrue(modelTypes.contains("LocalUTXO"))
        XCTAssertTrue(modelTypes.contains("SyncState"))
        XCTAssertTrue(modelTypes.contains("Balance"))
    }
    
    func testWalletSchemaV1VersionIdentifier() {
        // Given: WalletSchemaV1
        let version = WalletSchemaV1.versionIdentifier
        
        // Then: Should be version 1.0.0
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.patch, 0)
    }
    
    // MARK: - Migration Plan Tests
    
    func testWalletMigrationPlanSchemas() {
        // Given: WalletMigrationPlan
        let schemas = WalletMigrationPlan.schemas
        
        // Then: Should contain V1 schema
        XCTAssertEqual(schemas.count, 1)
        XCTAssertTrue(schemas.first is WalletSchemaV1.Type)
    }
    
    func testWalletMigrationPlanStages() {
        // Given: WalletMigrationPlan
        let stages = WalletMigrationPlan.stages
        
        // Then: Should have no stages (V1 is initial version)
        XCTAssertTrue(stages.isEmpty)
    }
    
    // MARK: - Container Creation with Migration Plan Tests
    
    func testCreateContainerWithMigrationPlan() throws {
        // Given: Clean state
        
        // When: Creating container with migration plan
        let container = try ModelContainerHelper.createContainer()
        
        // Then: Container should be created successfully
        XCTAssertNotNil(container)
        
        // Verify all models can be accessed
        let context = container.mainContext
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDWallet>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDAccount>()))
        XCTAssertNoThrow(try context.fetchCount(FetchDescriptor<HDWatchedAddress>()))
    }
    
    // MARK: - Future Migration Readiness Tests
    
    func testMigrationPlanStructure_ReadyForFutureVersions() {
        // This test verifies the migration plan is structured correctly
        // for future schema versions
        
        // Given: Current migration plan
        let migrationPlan = WalletMigrationPlan.self
        
        // Then: Should conform to SchemaMigrationPlan
        XCTAssertTrue(migrationPlan is any SchemaMigrationPlan.Type)
        
        // Verify we can add new schemas in the future
        // (This is a compile-time check - if it compiles, it's structured correctly)
        _ = migrationPlan.schemas
        _ = migrationPlan.stages
    }
    
    // MARK: - Data Persistence Through Container Recreation Tests
    
    func testDataPersistsThroughContainerRecreation() throws {
        // Given: Create initial container and add data
        var container = try ModelContainerHelper.createContainer()
        var context = container.mainContext
        
        let wallet = HDWallet(
            name: "Persistence Test",
            network: .testnet,
            encryptedSeed: Data(),
            seedHash: "persist-test"
        )
        
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub..."
        )
        
        let address = HDWatchedAddress(
            address: "yPERSISTTESTXXXXXXXXXXXXXXXXXXXXXX",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0"
        )
        
        context.insert(wallet)
        wallet.accounts.append(account)
        account.addresses.append(address)
        
        try context.save()
        
        let walletId = wallet.id
        let addressValue = address.address
        
        // When: Recreating container (simulating app restart)
        container = try ModelContainerHelper.createContainer()
        context = container.mainContext
        
        // Then: Data should persist
        let fetchedWallets = try context.fetch(FetchDescriptor<HDWallet>(
            predicate: #Predicate { $0.id == walletId }
        ))
        
        XCTAssertEqual(fetchedWallets.count, 1)
        XCTAssertEqual(fetchedWallets.first?.name, "Persistence Test")
        XCTAssertEqual(fetchedWallets.first?.accounts.count, 1)
        XCTAssertEqual(fetchedWallets.first?.accounts.first?.addresses.count, 1)
        XCTAssertEqual(fetchedWallets.first?.accounts.first?.addresses.first?.address, addressValue)
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyDatabaseWithMigrationPlan() throws {
        // Given: Clean state
        
        // When: Creating container with no data
        let container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        // Then: Should handle empty database gracefully
        let walletCount = try context.fetchCount(FetchDescriptor<HDWallet>())
        let addressCount = try context.fetchCount(FetchDescriptor<HDWatchedAddress>())
        
        XCTAssertEqual(walletCount, 0)
        XCTAssertEqual(addressCount, 0)
    }
    
    func testLargeDatasetWithMigrationPlan() throws {
        // Given: Container with migration plan
        let container = try ModelContainerHelper.createContainer()
        let context = container.mainContext
        
        // When: Creating large dataset
        let wallet = HDWallet(
            name: "Large Dataset Test",
            network: .mainnet,
            encryptedSeed: Data(),
            seedHash: "large-test"
        )
        context.insert(wallet)
        
        // Create multiple accounts with many addresses
        for accountIndex in 0..<5 {
            let account = HDAccount(
                accountIndex: UInt32(accountIndex),
                label: "Account \(accountIndex)",
                extendedPublicKey: "xpub\(accountIndex)..."
            )
            wallet.accounts.append(account)
            
            // Create many addresses per account
            for addressIndex in 0..<50 {
                let isChange = addressIndex >= 25
                let address = HDWatchedAddress(
                    address: "y\(accountIndex)\(addressIndex)\(String(repeating: "X", count: 30))",
                    index: UInt32(addressIndex),
                    isChange: isChange,
                    derivationPath: "m/44'/5'/\(accountIndex)'/\(isChange ? 1 : 0)/\(addressIndex)"
                )
                account.addresses.append(address)
            }
        }
        
        // Then: Should save successfully
        XCTAssertNoThrow(try context.save())
        
        // Verify counts
        let totalAddresses = try context.fetchCount(FetchDescriptor<HDWatchedAddress>())
        XCTAssertEqual(totalAddresses, 250) // 5 accounts * 50 addresses each
    }
}