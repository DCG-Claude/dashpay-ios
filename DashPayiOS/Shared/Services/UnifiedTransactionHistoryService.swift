import Foundation
import Combine
import SwiftData
import SwiftDashCoreSDK

/// Service that combines transaction history from all layers: Core, Platform, and Tokens
@MainActor
class UnifiedTransactionHistoryService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var transactions: [UnifiedTransaction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: Error?
    
    // MARK: - Dependencies
    
    private let coreSDK: DashSDKProtocol
    private let platformWrapper: PlatformSDKWrapper?
    private let tokenService: TokenService
    private let walletService: WalletService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        coreSDK: DashSDKProtocol,
        platformWrapper: PlatformSDKWrapper?,
        tokenService: TokenService,
        walletService: WalletService
    ) {
        self.coreSDK = coreSDK
        self.platformWrapper = platformWrapper
        self.tokenService = tokenService
        self.walletService = walletService
        
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Refresh all transaction history from all layers
    func refreshAllTransactions() async {
        isLoading = true
        error = nil
        
        do {
            let allTransactions = try await withThrowingTaskGroup(of: [UnifiedTransaction].self) { group in
                var results: [UnifiedTransaction] = []
                
                // Fetch Core transactions
                group.addTask {
                    return try await self.fetchCoreTransactions()
                }
                
                // Fetch Platform transactions (if available)
                if platformWrapper != nil {
                    group.addTask {
                        return try await self.fetchPlatformTransactions()
                    }
                }
                
                // Fetch Token transactions
                group.addTask {
                    return try await self.fetchTokenTransactions()
                }
                
                // Collect results
                for try await transactions in group {
                    results.append(contentsOf: transactions)
                }
                
                return results
            }
            
            // Sort by timestamp (newest first)
            transactions = allTransactions.sorted { $0.timestamp > $1.timestamp }
            lastUpdated = Date()
            
        } catch {
            self.error = error
            print("🔴 Failed to refresh transactions: \(error)")
        }
        
        isLoading = false
    }
    
    /// Get transactions filtered by type
    func getTransactions(ofType type: UnifiedTransactionType) -> [UnifiedTransaction] {
        return transactions.filter { $0.type == type }
    }
    
    /// Get transactions for a specific date range
    func getTransactions(from startDate: Date, to endDate: Date) -> [UnifiedTransaction] {
        return transactions.filter { transaction in
            transaction.timestamp >= startDate && transaction.timestamp <= endDate
        }
    }
    
    /// Get portfolio performance over time
    /// - Parameters:
    ///   - days: Number of days to look back (default: 30)
    ///   - initialBalance: Optional initial portfolio balance at the start date. If not provided,
    ///     the function will attempt to estimate the initial balance based on transaction history.
    /// - Returns: Array of portfolio data points showing value changes over time
    func getPortfolioHistory(days: Int = 30, initialBalance: Double? = nil) -> [PortfolioDataPoint] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            return []
        }
        
        let relevantTransactions = getTransactions(from: startDate, to: endDate)
        var portfolioHistory: [PortfolioDataPoint] = []
        
        // Initialize running balance with the actual portfolio balance at start date
        var runningBalance: Double
        if let initialBalance = initialBalance {
            // Use provided initial balance
            runningBalance = initialBalance
        } else {
            // Calculate initial balance by working backwards from current balance
            // For now, we'll estimate by calculating the cumulative effect of all transactions
            // from the start date to now and subtracting from a hypothetical current balance
            // This is a fallback approach since we don't have direct access to current wallet balance
            let transactionsFromStart = getTransactions(from: startDate, to: endDate)
            let netChangeFromStart = transactionsFromStart.reduce(0.0) { result, transaction in
                switch transaction.direction {
                case .received:
                    return result + transaction.dashValue
                case .sent:
                    return result - transaction.dashValue
                case .assetLock, .creditTransfer:
                    return result // These don't affect portfolio value directly
                }
            }
            // Initialize to zero for now - ideally this should be replaced with actual balance calculation
            // or the initialBalance parameter should be provided by the caller
            runningBalance = -netChangeFromStart // Start balance = current - net change
            print("⚠️ Portfolio history using estimated initial balance. Consider providing initialBalance parameter for accuracy.")
        }
        
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dayTransactions = relevantTransactions.filter { transaction in
                calendar.isDate(transaction.timestamp, inSameDayAs: currentDate)
            }
            
            // Calculate net change for the day
            let dayChange = dayTransactions.reduce(0.0) { result, transaction in
                switch transaction.direction {
                case .received:
                    return result + transaction.dashValue
                case .sent:
                    return result - transaction.dashValue
                case .assetLock, .creditTransfer:
                    return result // These don't affect portfolio value directly
                }
            }
            
            runningBalance += dayChange
            
            portfolioHistory.append(PortfolioDataPoint(
                date: currentDate,
                value: runningBalance,
                change: dayChange
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }
        
        return portfolioHistory
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Subscribe to Core SDK events for real-time updates
        if let coreSDK = coreSDK as? DashSDK {
            coreSDK.eventPublisher
                .sink { [weak self] event in
                    Task { @MainActor in
                        await self?.handleCoreEvent(event)
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func handleCoreEvent(_ event: SPVEvent) async {
        switch event {
        case .transactionReceived(let txid, _, _, _, _):
            print("🔄 New Core transaction detected: \(txid)")
            // Refresh transactions when new transaction is received
            await refreshAllTransactions()
            
        default:
            break
        }
    }
    
    private func fetchCoreTransactions() async throws -> [UnifiedTransaction] {
        guard let activeAccount = walletService.activeAccount else {
            return []
        }
        
        let sdkTransactions = await walletService.fetchTransactionsForAccount(activeAccount)
        
        return sdkTransactions.compactMap { sdkTransaction in
            convertToUnifiedTransaction(from: sdkTransaction)
        }
    }
    
    /// Convert SwiftDashCoreSDK.Transaction to UnifiedTransaction
    private func convertToUnifiedTransaction(from sdkTransaction: SwiftDashCoreSDK.Transaction) -> UnifiedTransaction? {
        // Determine transaction direction based on amount
        let direction: TransactionDirection = sdkTransaction.amount >= 0 ? .received : .sent
        
        // Determine transaction status based on confirmations
        let status: UnifiedTransactionStatus
        if sdkTransaction.confirmations == 0 {
            status = .pending
        } else if sdkTransaction.confirmations < 6 {
            status = .confirming
        } else {
            status = .confirmed
        }
        
        // Create core transaction metadata
        let metadata = CoreTransactionMetadata(
            isInstantSend: sdkTransaction.isInstantLocked,
            blockHeight: sdkTransaction.height
        )
        
        return UnifiedTransaction(
            id: sdkTransaction.txid,
            type: .coreTransaction,
            direction: direction,
            amount: UInt64(abs(sdkTransaction.amount)),
            dashValue: Double(abs(sdkTransaction.amount)) / 100_000_000.0,
            usdValue: 0.0, // TODO: Calculate USD value based on current exchange rate
            timestamp: sdkTransaction.timestamp,
            confirmations: sdkTransaction.confirmations,
            status: status,
            txid: sdkTransaction.txid,
            fromAddress: nil, // TODO: Extract from transaction data if needed
            toAddress: nil, // TODO: Extract from transaction data if needed
            fee: sdkTransaction.fee,
            metadata: metadata
        )
    }
    
    private func fetchPlatformTransactions() async throws -> [UnifiedTransaction] {
        // Fetch actual Platform transactions
        guard let platformSDK = platformWrapper else {
            print("⚠️ Platform SDK not available for transaction fetching")
            return []
        }
        
        // Implementation would go here - for now return empty array as Platform transactions
        // are handled differently through document operations
        return []
    }
    
    private func fetchTokenTransactions() async throws -> [UnifiedTransaction] {
        // Fetch actual Token transactions 
        // Use the tokenService property directly
        let tokenService = self.tokenService
        
        // Implementation would go here - token transactions are document-based operations
        // For now return empty array as this functionality is handled through the token service
        return []
    }
}

// MARK: - Models

struct UnifiedTransaction: Identifiable {
    let id: String
    let type: UnifiedTransactionType
    let direction: TransactionDirection
    let amount: UInt64 // Amount in smallest unit (satoshis for DASH, credits for Platform, token units for tokens)
    let dashValue: Double // Equivalent value in DASH
    let usdValue: Double // Equivalent value in USD
    let timestamp: Date
    let confirmations: UInt32
    let status: UnifiedTransactionStatus
    let txid: String
    let fromAddress: String?
    let toAddress: String?
    let fee: UInt64
    let metadata: TransactionMetadata
    
    var formattedAmount: String {
        switch type {
        case .coreTransaction:
            return String(format: "%.8g DASH", dashValue)
        case .identityCreation, .creditTransfer:
            return "\(amount) credits"
        case .tokenTransfer:
            if let tokenMetadata = metadata as? TokenTransactionMetadata {
                return "\(Double(amount) / 100_000_000) \(tokenMetadata.tokenSymbol)"
            }
            return "\(amount) tokens"
        }
    }
    
    var formattedUSDValue: String {
        return String(format: "$%.2f", usdValue)
    }
    
    var displayTitle: String {
        switch type {
        case .coreTransaction:
            return direction == .sent ? "Sent DASH" : "Received DASH"
        case .identityCreation:
            return "Identity Created"
        case .creditTransfer:
            return "Credit Transfer"
        case .tokenTransfer:
            if let tokenMetadata = metadata as? TokenTransactionMetadata {
                return "\(tokenMetadata.tokenSymbol) Transfer"
            }
            return "Token Transfer"
        }
    }
}

enum UnifiedTransactionType: String, Codable, CaseIterable {
    case coreTransaction = "core"
    case identityCreation = "identity_creation"
    case creditTransfer = "credit_transfer"
    case tokenTransfer = "token_transfer"
    
    var displayName: String {
        switch self {
        case .coreTransaction:
            return "Core Transaction"
        case .identityCreation:
            return "Identity Creation"
        case .creditTransfer:
            return "Credit Transfer"
        case .tokenTransfer:
            return "Token Transfer"
        }
    }
    
    var icon: String {
        switch self {
        case .coreTransaction:
            return "bitcoinsign.circle"
        case .identityCreation:
            return "person.badge.plus"
        case .creditTransfer:
            return "arrow.left.arrow.right.circle"
        case .tokenTransfer:
            return "circle.grid.hex"
        }
    }
}

enum TransactionDirection: String, Codable {
    case sent
    case received
    case assetLock
    case creditTransfer
    
    var icon: String {
        switch self {
        case .sent:
            return "arrow.up.circle"
        case .received:
            return "arrow.down.circle"
        case .assetLock:
            return "lock.circle"
        case .creditTransfer:
            return "arrow.left.arrow.right.circle"
        }
    }
    
    var color: String {
        switch self {
        case .sent:
            return "red"
        case .received:
            return "green"
        case .assetLock:
            return "orange"
        case .creditTransfer:
            return "blue"
        }
    }
}

enum UnifiedTransactionStatus: String, Codable {
    case pending
    case confirming
    case confirmed
    case failed
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .confirming:
            return "Confirming"
        case .confirmed:
            return "Confirmed"
        case .failed:
            return "Failed"
        }
    }
    
    var color: String {
        switch self {
        case .pending:
            return "orange"
        case .confirming:
            return "yellow"
        case .confirmed:
            return "green"
        case .failed:
            return "red"
        }
    }
}

// MARK: - Transaction Metadata

protocol TransactionMetadata: Codable {
    // Base protocol for transaction metadata
}

struct CoreTransactionMetadata: TransactionMetadata {
    let isInstantSend: Bool
    let blockHeight: UInt32?
}

struct PlatformTransactionMetadata: TransactionMetadata {
    let identityId: String
    let operation: String
    let creditsUsed: UInt64
}

struct TokenTransactionMetadata: TransactionMetadata {
    let tokenContractId: String
    let tokenSymbol: String
    let tokenName: String
    let fromIdentityId: String?
    let toIdentityId: String?
}

// MARK: - Portfolio Data

struct PortfolioDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double // Total portfolio value in DASH
    let change: Double // Change for this period
    
    var formattedValue: String {
        return String(format: "%.6f DASH", value)
    }
    
    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.6f", change))"
    }
}