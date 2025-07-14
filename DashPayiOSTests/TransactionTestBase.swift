import XCTest
import SwiftData
import Foundation
@testable import DashPay

// Define missing types for tests
enum DashNetwork: String {
    case mainnet = "mainnet"
    case testnet = "testnet"
    case devnet = "devnet"
    case regtest = "regtest"
    
    var name: String { rawValue }
}

enum TransactionStatus: Equatable, CustomStringConvertible {
    case pending
    case confirming(confirmations: Int)
    case confirmed
    case instantLocked
    case failed
    case conflicted
    
    var description: String {
        switch self {
        case .pending: return "Pending"
        case .confirming(let confirmations): return "Confirming (\(confirmations))"
        case .confirmed: return "Confirmed"
        case .instantLocked: return "InstantLocked"
        case .failed: return "Failed"
        case .conflicted: return "Conflicted"
        }
    }
    
    var isSettled: Bool {
        switch self {
        case .confirmed, .instantLocked:
            return true
        default:
            return false
        }
    }
}

@Model
class UTXO {
    var outpoint: String
    var txid: String
    var vout: UInt32
    var address: String
    var script: Data
    var value: UInt64
    var height: UInt32
    var confirmations: UInt32
    var isInstantLocked: Bool
    var isSpent: Bool = false
    
    init(outpoint: String, txid: String, vout: UInt32, address: String, script: Data, value: UInt64, height: UInt32, confirmations: UInt32, isInstantLocked: Bool) {
        self.outpoint = outpoint
        self.txid = txid
        self.vout = vout
        self.address = address
        self.script = script
        self.value = value
        self.height = height
        self.confirmations = confirmations
        self.isInstantLocked = isInstantLocked
    }
    
    var isSpendable: Bool {
        return !isSpent && confirmations > 0
    }
    
    static func createOutpoint(txid: String, vout: UInt32) -> String {
        return "\(txid):\(vout)"
    }
}

@Model
class Balance {
    var confirmed: UInt64
    var pending: UInt64
    var instantLocked: UInt64
    var mempool: UInt64
    var mempoolInstant: UInt64
    var total: UInt64
    
    init(confirmed: UInt64, pending: UInt64, instantLocked: UInt64, mempool: UInt64, mempoolInstant: UInt64, total: UInt64) {
        self.confirmed = confirmed
        self.pending = pending
        self.instantLocked = instantLocked
        self.mempool = mempool
        self.mempoolInstant = mempoolInstant
        self.total = total
    }
}

@Model
class Transaction {
    var txid: String
    var height: UInt32?
    var timestamp: Date
    var amount: Int64
    var fee: UInt64
    var confirmations: UInt32
    var isInstantLocked: Bool
    var raw: Data
    var size: Int
    var version: Int32
    
    var status: TransactionStatus {
        // Calculate status based on state
        if isInstantLocked {
            return .instantLocked
        } else if confirmations >= 6 {
            return .confirmed
        } else if confirmations > 0 {
            return .confirming(confirmations: Int(confirmations))
        } else {
            return .pending
        }
    }
    
    var isPending: Bool {
        return status == .pending
    }
    
    var isConfirmed: Bool {
        switch status {
        case .confirmed, .instantLocked:
            return true
        default:
            return false
        }
    }
    
    init(txid: String, height: UInt32?, timestamp: Date, amount: Int64, fee: UInt64, confirmations: UInt32, isInstantLocked: Bool, raw: Data, size: Int, version: Int32) {
        self.txid = txid
        self.height = height
        self.timestamp = timestamp
        self.amount = amount
        self.fee = fee
        self.confirmations = confirmations
        self.isInstantLocked = isInstantLocked
        self.raw = raw
        self.size = size
        self.version = version
    }
}

struct SPVClientConfiguration {
    var network: DashNetwork = .testnet
    var validationMode: ValidationMode = .full
    var mempoolConfig: MempoolConfig = .fetchAll(maxTransactions: 1000)
    
    enum ValidationMode {
        case none, basic, full
    }
    
    enum MempoolConfig {
        case disabled
        case fetchAll(maxTransactions: Int)
        case selective
    }
    
    static func testnet() -> SPVClientConfiguration {
        return SPVClientConfiguration(network: .testnet)
    }
    
    static func mainnet() -> SPVClientConfiguration {
        return SPVClientConfiguration(network: .mainnet)
    }
}

@Model
class HDWallet {
    var name: String
    private var networkRaw: String
    var encryptedSeed: Data
    var seedHash: String
    var accounts: [HDAccount] = []
    var lastSynced: Date?
    
    var network: DashNetwork {
        get { DashNetwork(rawValue: networkRaw) ?? .testnet }
        set { networkRaw = newValue.rawValue }
    }
    
    init(name: String, network: DashNetwork, encryptedSeed: Data, seedHash: String) {
        self.name = name
        self.networkRaw = network.rawValue
        self.encryptedSeed = encryptedSeed
        self.seedHash = seedHash
    }
}

@Model
class HDAccount {
    var accountIndex: UInt32
    var label: String
    var extendedPublicKey: String
    var wallet: HDWallet?
    var addresses: [HDWatchedAddress] = []
    
    init(accountIndex: UInt32, label: String, extendedPublicKey: String) {
        self.accountIndex = accountIndex
        self.label = label
        self.extendedPublicKey = extendedPublicKey
    }
}

@Model
class HDWatchedAddress {
    var address: String
    var index: UInt32
    var isChange: Bool
    var derivationPath: String
    var label: String?
    var account: HDAccount?
    
    init(address: String, index: UInt32, isChange: Bool, derivationPath: String, label: String? = nil) {
        self.address = address
        self.index = index
        self.isChange = isChange
        self.derivationPath = derivationPath
        self.label = label
    }
}

/// Base class for all transaction-related tests providing common utilities and test data
@MainActor
class TransactionTestBase: XCTestCase {
    
    // MARK: - Test Infrastructure
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var walletService: WalletService!
    var testWallet: HDWallet!
    var testAccount: HDAccount!
    
    // MARK: - Test Networks
    
    let testnetNetwork: DashNetwork = .testnet
    let mainnetNetwork: DashNetwork = .mainnet
    
    // MARK: - Test Constants
    
    struct TestConstants {
        static let defaultTimeout: TimeInterval = 30.0
        static let networkTimeout: TimeInterval = 60.0
        static let minDustAmount: UInt64 = 546 // Minimum non-dust output in satoshis
        static let standardFeeRate: UInt64 = 1000 // satoshis per KB
        static let fastFeeRate: UInt64 = 2000
        static let slowFeeRate: UInt64 = 500
        
        // Test amounts in satoshis
        static let smallAmount: UInt64 = 10_000_000 // 0.1 DASH
        static let mediumAmount: UInt64 = 100_000_000 // 1.0 DASH
        static let largeAmount: UInt64 = 1_000_000_000 // 10.0 DASH
    }
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory model container for testing
        let schema = Schema([
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Balance.self,
            Transaction.self,
            UTXO.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = modelContainer.mainContext
        
        // Initialize WalletService
        walletService = WalletService.shared
        walletService.configure(modelContext: modelContext)
        
        // Create test wallet and account
        testWallet = createTestWallet()
        testAccount = createTestAccount()
    }
    
    override func tearDownWithError() throws {
        // Clean up
        walletService = nil
        testAccount = nil
        testWallet = nil
        modelContainer = nil
        modelContext = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Test Data Factory Methods
    
    /// Creates a test wallet for testing purposes
    func createTestWallet(
        name: String = "Test Wallet",
        network: DashNetwork = .testnet
    ) -> HDWallet {
        let wallet = HDWallet(
            name: name,
            network: network,
            encryptedSeed: generateTestSeed(),
            seedHash: generateTestSeedHash()
        )
        modelContext.insert(wallet)
        return wallet
    }
    
    /// Creates a test account for the given wallet
    func createTestAccount(
        wallet: HDWallet? = nil,
        index: UInt32 = 0,
        label: String = "Test Account"
    ) -> HDAccount {
        let targetWallet = wallet ?? testWallet!
        let account = HDAccount(
            accountIndex: index,
            label: label,
            extendedPublicKey: generateTestXpub(index: index)
        )
        account.wallet = targetWallet
        targetWallet.accounts.append(account)
        modelContext.insert(account)
        return account
    }
    
    /// Creates a test address for the given account
    func createTestAddress(
        account: HDAccount? = nil,
        index: UInt32 = 0,
        isChange: Bool = false,
        network: DashNetwork = .testnet
    ) -> HDWatchedAddress {
        let targetAccount = account ?? testAccount!
        let address = generateTestAddress(index: index, isChange: isChange, network: network)
        let derivationPath = generateDerivationPath(
            network: network,
            account: targetAccount.accountIndex,
            change: isChange,
            index: index
        )
        
        let watchedAddress = HDWatchedAddress(
            address: address,
            index: index,
            isChange: isChange,
            derivationPath: derivationPath,
            label: isChange ? "Change" : "Receive"
        )
        watchedAddress.account = targetAccount
        targetAccount.addresses.append(watchedAddress)
        modelContext.insert(watchedAddress)
        return watchedAddress
    }
    
    /// Creates a test UTXO
    func createTestUTXO(
        txid: String? = nil,
        vout: UInt32 = 0,
        address: String? = nil,
        value: UInt64 = TestConstants.mediumAmount,
        height: UInt32 = 100000,
        confirmations: UInt32 = 6,
        isInstantLocked: Bool = false
    ) -> UTXO {
        let utxoTxid = txid ?? generateTestTxid()
        let utxoAddress = address ?? generateTestAddress(index: 0, isChange: false, network: .testnet)
        let outpoint = UTXO.createOutpoint(txid: utxoTxid, vout: vout)
        
        let utxo = UTXO(
            outpoint: outpoint,
            txid: utxoTxid,
            vout: vout,
            address: utxoAddress,
            script: generateTestScript(),
            value: value,
            height: height,
            confirmations: confirmations,
            isInstantLocked: isInstantLocked
        )
        modelContext.insert(utxo)
        return utxo
    }
    
    /// Creates a test transaction
    func createTestTransaction(
        txid: String? = nil,
        amount: Int64 = Int64(TestConstants.mediumAmount),
        height: UInt32? = 100000,
        confirmations: UInt32 = 6,
        isInstantLocked: Bool = false,
        fee: UInt64 = 1000
    ) -> Transaction {
        let transaction = Transaction(
            txid: txid ?? generateTestTxid(),
            height: height,
            timestamp: Date(),
            amount: amount,
            fee: fee,
            confirmations: confirmations,
            isInstantLocked: isInstantLocked,
            raw: generateTestRawTransaction(),
            size: 250,
            version: 3
        )
        modelContext.insert(transaction)
        return transaction
    }
    
    // MARK: - Test Address Generation
    
    func generateTestAddress(index: UInt32, isChange: Bool, network: DashNetwork) -> String {
        let prefix = network == .mainnet ? "X" : "y"
        let changeChar = isChange ? "c" : "r"
        return "\(prefix)\(changeChar)\(String(format: "%08x", index))TestAddress"
    }
    
    func generateValidTestnetAddress() -> String {
        return "yP8A3q8vhQNZNrxJQgJ7VjSkZ5EjyzMEvH"
    }
    
    func generateValidMainnetAddress() -> String {
        return "XmNhYPZaRnJbMJrGJqJ9N4A8Lz3F9NaYjJ"
    }
    
    func generateInvalidAddress() -> String {
        return "invalid_address_format"
    }
    
    // MARK: - Test Transaction Data Generation
    
    func generateTestTxid() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    
    func generateTestSeed() -> Data {
        return Data("test_seed_\(UUID().uuidString)".utf8)
    }
    
    func generateTestSeedHash() -> String {
        return "test_hash_\(UUID().uuidString)"
    }
    
    func generateTestXpub(index: UInt32) -> String {
        return "xpub661MyMwAqRbcF\(index)TestXpub"
    }
    
    func generateTestScript() -> Data {
        // Generate a simple P2PKH script
        let script = Data([0x76, 0xA9, 0x14]) + Data(repeating: 0x00, count: 20) + Data([0x88, 0xAC])
        return script
    }
    
    func generateTestRawTransaction() -> Data {
        // Generate a minimal valid transaction structure
        var rawTx = Data()
        
        // Version (4 bytes)
        rawTx.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Array($0) })
        
        // Input count (1 byte)
        rawTx.append(0x01)
        
        // Previous output hash (32 bytes)
        rawTx.append(Data(repeating: 0x00, count: 32))
        
        // Previous output index (4 bytes)
        rawTx.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        
        // Script length (1 byte)
        rawTx.append(0x00)
        
        // Sequence (4 bytes)
        rawTx.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF).littleEndian) { Array($0) })
        
        // Output count (1 byte)
        rawTx.append(0x01)
        
        // Output value (8 bytes)
        rawTx.append(contentsOf: withUnsafeBytes(of: UInt64(100000000).littleEndian) { Array($0) })
        
        // Output script length (1 byte)
        rawTx.append(0x19) // 25 bytes for P2PKH
        
        // Output script (25 bytes)
        rawTx.append(generateTestScript())
        
        // Locktime (4 bytes)
        rawTx.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        
        return rawTx
    }
    
    func generateDerivationPath(
        network: DashNetwork,
        account: UInt32,
        change: Bool,
        index: UInt32
    ) -> String {
        let coinType = network == .mainnet ? 5 : 1
        let changeValue = change ? 1 : 0
        return "m/44'/\(coinType)'/\(account)'/\(changeValue)/\(index)"
    }
    
    // MARK: - Test Validation Helpers
    
    func validateDashAddress(_ address: String, network: DashNetwork) -> Bool {
        guard !address.isEmpty else { return false }
        
        let firstChar = address.first!
        switch network {
        case .mainnet:
            return firstChar == "X" || firstChar == "7"
        case .testnet, .devnet, .regtest:
            return firstChar == "y" || firstChar == "8" || firstChar == "9"
        }
    }
    
    
    func parseDashAmount(_ dashString: String) -> UInt64? {
        guard let dash = Double(dashString) else { return nil }
        return UInt64(dash * 100_000_000)
    }
    
    // MARK: - Test Assertion Helpers
    
    func assertTransactionStatus(_ transaction: Transaction, expectedStatus: TransactionStatus, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(transaction.status, expectedStatus, "Transaction status mismatch", file: file, line: line)
    }
    
    func assertBalanceEquals(_ balance: Balance?, expected: UInt64, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNotNil(balance, "Balance should not be nil", file: file, line: line)
        XCTAssertEqual(balance?.total, expected, "Balance total mismatch", file: file, line: line)
    }
    
    func assertUTXOSpendable(_ utxo: UTXO, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(utxo.isSpendable, "UTXO should be spendable", file: file, line: line)
    }
    
    func assertUTXONotSpendable(_ utxo: UTXO, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(utxo.isSpendable, "UTXO should not be spendable", file: file, line: line)
    }
    
    // MARK: - Network Testing Helpers
    
    func createTestnetConfiguration() -> SPVClientConfiguration {
        let config = SPVClientConfiguration()
        config.network = .testnet
        config.validationMode = .full
        config.mempoolConfig = .fetchAll(maxTransactions: 1000)
        return config
    }
    
    func waitForAsyncOperation<T>(
        timeout: TimeInterval = TestConstants.defaultTimeout,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw XCTestError(.timeoutWhileWaiting)
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Mock Balance Creation
    
    func createMockLocalBalance(
        confirmed: UInt64 = 0,
        pending: UInt64 = 0,
        instantLocked: UInt64 = 0,
        mempool: UInt64 = 0,
        mempoolInstant: UInt64 = 0
    ) -> Balance {
        let total = confirmed + pending + mempool
        return LocalBalance(
            confirmed: confirmed,
            pending: pending,
            instantLocked: instantLocked,
            mempool: mempool,
            mempoolInstant: mempoolInstant,
            total: total
        )
    }
    
    // MARK: - Test Data Cleanup
    
    func cleanupTestData() {
        do {
            // Delete all test objects
            let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            for transaction in transactions {
                modelContext.delete(transaction)
            }
            
            let utxos = try modelContext.fetch(FetchDescriptor<UTXO>())
            for utxo in utxos {
                modelContext.delete(utxo)
            }
            
            let balances = try modelContext.fetch(FetchDescriptor<Balance>())
            for balance in balances {
                modelContext.delete(balance)
            }
            
            try modelContext.save()
        } catch {
            XCTFail("Failed to cleanup test data: \(error)")
        }
    }
    
    // MARK: - dash-cli Integration Helpers
    
    /// Helper to check if dash-cli is available for real network testing
    func isDashCliAvailable() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["dash-cli"]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
    
    /// Generate a command to send testnet funds using dash-cli
    func generateDashCliSendCommand(to address: String, amount: Double) -> String {
        return "dash-cli -testnet sendtoaddress \(address) \(amount)"
    }
    
    /// Generate a command to get testnet balance using dash-cli
    func generateDashCliBalanceCommand() -> String {
        return "dash-cli -testnet getbalance"
    }
}

// MARK: - Test Error Types

enum TransactionTestError: Error, LocalizedError {
    case invalidTestData
    case networkNotAvailable
    case timeoutWaitingForConfirmation
    case insufficientTestFunds
    case invalidAddress
    case transactionBuildFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidTestData:
            return "Invalid test data provided"
        case .networkNotAvailable:
            return "Network not available for testing"
        case .timeoutWaitingForConfirmation:
            return "Timeout waiting for transaction confirmation"
        case .insufficientTestFunds:
            return "Insufficient test funds for transaction"
        case .invalidAddress:
            return "Invalid address format"
        case .transactionBuildFailed:
            return "Failed to build transaction"
        }
    }
}

// MARK: - Test Expectations Helper

extension XCTestCase {
    func expectation(for condition: @escaping () -> Bool, timeout: TimeInterval = 10.0, description: String = "Condition") -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if condition() {
                expectation.fulfill()
                timer.invalidate()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            timer.invalidate()
        }
        
        return expectation
    }
}