import Foundation
import SwiftData
import SwiftDashCoreSDK

// MARK: - HD Wallet

/// Thread-Safety Documentation for HDWallet
/// 
/// This class is marked with @unchecked Sendable to bypass Swift's automatic
/// concurrency safety checks. Thread-safety guarantees:
///
/// SAFE OPERATIONS (can be performed from any thread):
/// - Reading immutable properties after initialization (id, name, network, createdAt, seedHash)
/// - Reading encryptedSeed (immutable after init, but handle with security considerations)
/// - Accessing computed properties (displayNetwork, totalBalance)
///
/// MAIN ACTOR REQUIRED OPERATIONS:
/// - All SwiftData model operations (save, insert, delete, relationship updates)
/// - Modifying lastSynced property
/// - Adding/removing accounts through the @Relationship
/// - Any write operations to persisted properties
///
/// IMPORTANT CONCURRENCY CONSIDERATIONS:
/// 1. SwiftData requires all model operations to occur on the @MainActor
/// 2. The encryptedSeed contains sensitive data and should be handled with appropriate
///    security measures regardless of thread
/// 3. The totalBalance computed property aggregates data from related accounts,
///    ensure accounts relationship is accessed from @MainActor context
/// 4. When passing HDWallet instances across actor boundaries, ensure immutable
///    access patterns or proper actor-isolated operations
///
/// USAGE GUIDELINES:
/// - Always perform model persistence operations within @MainActor context
/// - Use appropriate synchronization when accessing mutable state
/// - Be cautious with sensitive data (encryptedSeed) across thread boundaries
@Model
final class HDWallet: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var name: String
    var network: DashNetwork
    var createdAt: Date
    var lastSynced: Date?
    var encryptedSeed: Data // Encrypted mnemonic seed
    var seedHash: String // For duplicate detection
    
    @Relationship(deleteRule: .cascade) var accounts: [HDAccount]
    
    init(name: String, network: DashNetwork, encryptedSeed: Data, seedHash: String) {
        self.id = UUID()
        self.name = name
        self.network = network
        self.createdAt = Date()
        self.encryptedSeed = encryptedSeed
        self.seedHash = seedHash
        self.accounts = []
    }
    
    var displayNetwork: String {
        switch network {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .regtest:
            return "Regtest"
        case .devnet:
            return "Devnet"
        }
    }
    
    var totalBalance: SwiftDashCoreSDK.Balance {
        var confirmed: UInt64 = 0
        var pending: UInt64 = 0
        var instantLocked: UInt64 = 0
        var mempool: UInt64 = 0
        var mempoolInstant: UInt64 = 0
        var total: UInt64 = 0
        
        for account in accounts {
            if let accountBalance = account.balance {
                confirmed += accountBalance.confirmed
                pending += accountBalance.pending
                instantLocked += accountBalance.instantLocked
                mempool += accountBalance.mempool
                mempoolInstant += accountBalance.mempoolInstant
                total += accountBalance.total
            }
        }
        
        // Create a non-persisted balance object for display purposes
        return SwiftDashCoreSDK.Balance(
            confirmed: confirmed,
            pending: pending,
            instantLocked: instantLocked,
            mempool: mempool,
            mempoolInstant: mempoolInstant,
            total: total,
            lastUpdated: Date()
        )
    }
}

// MARK: - HD Account (BIP44)

@Model
final class HDAccount: @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    var accountIndex: UInt32
    var label: String
    var extendedPublicKey: String // xpub for this account
    var createdAt: Date
    var lastUsedExternalIndex: UInt32
    var lastUsedInternalIndex: UInt32
    var gapLimit: UInt32
    
    @Relationship var wallet: HDWallet
    @Relationship(deleteRule: .cascade) var balance: LocalBalance?
    @Relationship(deleteRule: .cascade) var addresses: [HDWatchedAddress]
    // Transaction IDs associated with this account
    var transactionIds: [String] = []
    
    init(
        accountIndex: UInt32,
        label: String,
        extendedPublicKey: String,
        gapLimit: UInt32 = 20
    ) {
        self.id = UUID()
        self.accountIndex = accountIndex
        self.label = label
        self.extendedPublicKey = extendedPublicKey
        self.createdAt = Date()
        self.lastUsedExternalIndex = 0
        self.lastUsedInternalIndex = 0
        self.gapLimit = gapLimit
        self.addresses = []
    }
    
    var displayName: String {
        return label.isEmpty ? "Account #\(accountIndex)" : label
    }
    
    var derivationPath: String {
        let coinType: UInt32 = wallet.network == .mainnet ? 5 : 1
        return "m/44'/\(coinType)'/\(accountIndex)'"
    }
    
    var externalAddresses: [HDWatchedAddress] {
        addresses.filter { !$0.isChange }.sorted { $0.index < $1.index }
    }
    
    var internalAddresses: [HDWatchedAddress] {
        addresses.filter { $0.isChange }.sorted { $0.index < $1.index }
    }
    
    var receiveAddress: HDWatchedAddress? {
        // Find the first unused address or the next one to generate
        return externalAddresses.first { $0.transactionIds.isEmpty }
    }
}

// MARK: - HD Watched Address

@Model
public final class HDWatchedAddress: @unchecked Sendable {
    @Attribute(.unique) var address: String
    var label: String?
    var createdAt: Date
    var lastActive: Date?
    var lastActivityTimestamp: Date? // For tracking recent transaction activity
    var balance: LocalBalance?
    // Transaction IDs associated with this address (stored as JSON string)
    private var transactionIdsData: String = "[]"
    // UTXO outpoints associated with this address (stored as JSON string)
    private var utxoOutpointsData: String = "[]"
    
    var transactionIds: [String] {
        get {
            guard let data = transactionIdsData.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let jsonString = String(data: data, encoding: .utf8) else {
                transactionIdsData = "[]"
                return
            }
            transactionIdsData = jsonString
        }
    }
    
    var utxoOutpoints: [String] {
        get {
            guard let data = utxoOutpointsData.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let jsonString = String(data: data, encoding: .utf8) else {
                utxoOutpointsData = "[]"
                return
            }
            utxoOutpointsData = jsonString
        }
    }
    
    // HD specific properties
    var index: UInt32
    var isChange: Bool
    var derivationPath: String
    @Relationship(inverse: \HDAccount.addresses) var account: HDAccount?
    
    init(address: String, index: UInt32, isChange: Bool, derivationPath: String, label: String? = nil) {
        self.address = address
        self.index = index
        self.isChange = isChange
        self.derivationPath = derivationPath
        self.label = label
        self.createdAt = Date()
        // Note: balance is left nil and created lazily when needed to avoid SwiftData persistence issues
    }
    
    var formattedBalance: String {
        guard let balance = balance else { return "0.00000000 DASH" }
        return balance.formattedTotal
    }
    
    /// Factory method to create initial balance when needed
    /// Should be called from a SwiftData context to ensure proper persistence
    func createInitialBalance() -> LocalBalance {
        let newBalance = LocalBalance(
            confirmed: 0,
            pending: 0,
            instantLocked: 0,
            mempool: 0,
            mempoolInstant: 0,
            total: 0,
            lastUpdated: Date()
        )
        self.balance = newBalance
        return newBalance
    }
}

// MARK: - Transaction Helper
// Transaction type is provided by SwiftDashCoreSDK and doesn't need conversion

// MARK: - Sync State

@Model
final class SyncState: @unchecked Sendable {
    @Attribute(.unique) var walletId: UUID
    var currentHeight: UInt32
    var totalHeight: UInt32
    var progress: Double
    var status: String
    var lastError: String?
    var startTime: Date
    var estimatedCompletion: Date?
    
    init(walletId: UUID) {
        self.walletId = walletId
        self.currentHeight = 0
        self.totalHeight = 0
        self.progress = 0
        self.status = "idle"
        self.startTime = Date()
    }
    
    func update(from syncProgress: SyncProgress) {
        self.currentHeight = syncProgress.currentHeight
        self.totalHeight = syncProgress.totalHeight
        self.progress = syncProgress.progress
        self.status = syncProgress.status.rawValue
        
        if let eta = syncProgress.estimatedTimeRemaining {
            self.estimatedCompletion = Date().addingTimeInterval(eta)
        }
    }
}

// MARK: - Balance Update Extensions

extension HDAccount {
    
    /// Safely update account balance using SwiftData best practices
    @MainActor
    func updateBalanceSafely(from sdkBalance: SwiftDashCoreSDK.Balance, in context: ModelContext) throws {
        // Ensure we're on main thread for SwiftData operations
        assert(Thread.isMainThread, "SwiftData operations must be on main thread")
        
        if let existingBalance = self.balance {
            // Update existing balance
            existingBalance.update(from: sdkBalance)
        } else {
            // Create new balance from SDK balance with safe defaults
            let newBalance = LocalBalance(
                confirmed: sdkBalance.confirmed,
                pending: sdkBalance.pending,
                instantLocked: sdkBalance.instantLocked,
                mempool: sdkBalance.mempool,
                mempoolInstant: sdkBalance.mempoolInstant ?? 0,
                total: sdkBalance.total,
                lastUpdated: sdkBalance.lastUpdated
            )
            // SwiftData automatically handles inserting related objects when the relationship is set
            self.balance = newBalance
        }
        // Save after relationship is established
        try context.save()
    }
    
    /// Create or update balance safely for test scenarios
    @MainActor
    func createOrUpdateBalance(from balanceData: LocalBalance, in context: ModelContext) throws {
        if let existingBalance = self.balance {
            existingBalance.update(from: balanceData)
        } else {
            let newBalance = LocalBalance(
                confirmed: balanceData.confirmed,
                pending: balanceData.pending,
                instantLocked: balanceData.instantLocked,
                mempool: balanceData.mempool,
                mempoolInstant: balanceData.mempoolInstant,
                total: balanceData.total
            )
            // Important: Don't insert separately, just assign to relationship
            // SwiftData will handle the insertion when the relationship is set
            self.balance = newBalance
        }
        try context.save()
    }
}

extension HDWatchedAddress {
    
    /// Safely update watched address balance using SwiftData best practices
    @MainActor
    func updateBalanceSafely(from sdkBalance: SwiftDashCoreSDK.Balance, in context: ModelContext) throws {
        // Ensure we're on main thread for SwiftData operations
        assert(Thread.isMainThread, "SwiftData operations must be on main thread")
        
        if let existingBalance = self.balance {
            // Update existing balance
            existingBalance.update(from: sdkBalance)
        } else {
            // Create new balance from SDK balance with safe defaults
            let newBalance = LocalBalance(
                confirmed: sdkBalance.confirmed,
                pending: sdkBalance.pending,
                instantLocked: sdkBalance.instantLocked,
                mempool: sdkBalance.mempool,
                mempoolInstant: sdkBalance.mempoolInstant ?? 0,
                total: sdkBalance.total,
                lastUpdated: sdkBalance.lastUpdated
            )
            // Insert the balance into the context first
            context.insert(newBalance)
            // Then assign to relationship
            self.balance = newBalance
        }
        // Save after relationship is established
        try context.save()
    }
    
    /// Create or update balance safely for test scenarios
    @MainActor
    func updateBalanceSafely(to newBalance: LocalBalance, in context: ModelContext) throws {
        if let existingBalance = self.balance {
            // Update existing balance in place
            existingBalance.update(from: newBalance)
        } else {
            // Create new balance
            let balance = LocalBalance(
                confirmed: newBalance.confirmed,
                pending: newBalance.pending,
                instantLocked: newBalance.instantLocked,
                mempool: newBalance.mempool,
                mempoolInstant: newBalance.mempoolInstant,
                total: newBalance.total
            )
            // Insert the balance into the context first
            context.insert(balance)
            // Then assign to relationship
            self.balance = balance
        }
        try context.save()
    }
}