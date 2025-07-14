import Foundation
import Combine
import SwiftData
import UserNotifications
import SwiftDashCoreSDK

/// Manages unified state across Core and Platform layers
@MainActor
class UnifiedStateManager: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var unifiedBalance = UnifiedBalance()
    @Published private(set) var wallets: [Wallet] = []
    @Published internal(set) var identities: [Identity] = []
    // Removed duplicate sync tracking - use WalletService.detailedSyncProgress instead
    @Published private(set) var isPlatformSynced = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - Dependencies
    
    private var coreSDK: DashSDKProtocol
    internal var platformWrapper: PlatformSDKWrapper?
    internal var assetLockBridge: AssetLockBridge?
    private var crossLayerBridge: CrossLayerBridge?
    private var transactionHistory: UnifiedTransactionHistoryService?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(coreSDK: DashSDKProtocol, platformWrapper: PlatformSDKWrapper?) {
        self.coreSDK = coreSDK
        self.platformWrapper = platformWrapper
        
        // AssetLockBridge and related services need to be created in an async context since they're actors
        Task {
            if let platformWrapper = platformWrapper {
                let assetLockBridge = await AssetLockBridge(
                    coreSDK: coreSDK,
                    platformSDK: platformWrapper
                )
                self.assetLockBridge = assetLockBridge
                
                // Create CrossLayerBridge
                self.crossLayerBridge = await CrossLayerBridge(
                    coreSDK: coreSDK,
                    platformSDK: platformWrapper,
                    assetLockBridge: assetLockBridge
                )
                
                // Create transaction history service
                self.transactionHistory = UnifiedTransactionHistoryService(
                    coreSDK: coreSDK,
                    platformWrapper: platformWrapper,
                    tokenService: TokenService()
                )
            }
        }
        
        setupSubscriptions()
    }
    
    func updatePlatformWrapper(_ wrapper: PlatformSDKWrapper) async {
        self.platformWrapper = wrapper
        self.assetLockBridge = await AssetLockBridge(
            coreSDK: coreSDK,
            platformSDK: wrapper
        )
    }
    
    func updateCoreSDK(_ sdk: DashSDKProtocol) async {
        self.coreSDK = sdk
        if let platformWrapper = platformWrapper {
            self.assetLockBridge = await AssetLockBridge(
                coreSDK: sdk,
                platformSDK: platformWrapper
            )
        }
    }
    
    // MARK: - Public Methods
    
    /// Initialize with a mock wallet for testing
    func initializeWithMockWallet() {
        let mockWallet = Wallet(
            id: "mock-wallet-1",
            balance: 10_000_000_000, // 100 DASH
            address: "yXxJ9TK4xd6c6cXPWzY5Z7h7vF5vLqVH8B"
        )
        wallets = [mockWallet]
        updateCoreBalance(mockWallet.balance)
    }
    
    /// Update Core wallet balance
    func updateCoreBalance(_ balance: UInt64) {
        unifiedBalance.coreBalance = balance
    }
    
    /// Update Platform credit balance
    func updatePlatformCredits(_ credits: UInt64) {
        unifiedBalance.platformCredits = credits
    }
    
    /// Update token balance with full metadata
    func updateTokenBalance(_ tokenBalance: TokenBalance) {
        unifiedBalance.tokenBalances[tokenBalance.tokenId] = tokenBalance
    }
    
    /// Update token balance (legacy method for compatibility)
    func updateTokenBalance(_ tokenId: String, balance: UInt64) {
        // Create a basic TokenBalance for legacy compatibility
        let tokenBalance = TokenBalance(
            tokenId: tokenId,
            balance: balance,
            symbol: "UNKNOWN",
            name: "Unknown Token",
            decimals: 8,
            contractId: "",
            dashValue: 0.0,
            usdValue: 0.0,
            pricePerToken: 0.0,
            change24h: 0.0
        )
        unifiedBalance.tokenBalances[tokenId] = tokenBalance
    }
    
    /// Update price data for portfolio calculations
    func updatePriceData(_ priceData: PriceData) {
        unifiedBalance.priceData = priceData
    }
    
    /// Refresh price data from external sources
    func refreshPriceData() async {
        // Price fetching would integrate with external price APIs in a production app
        // For now, simulate price updates
        let mockPriceData = PriceData(
            dashPriceUSD: Double.random(in: 45...55),
            dashPriceUSD24hAgo: unifiedBalance.priceData.dashPriceUSD,
            creditToUSDRate: 0.000001,
            lastUpdated: Date()
        )
        
        updatePriceData(mockPriceData)
    }
    
    /// Refresh sync state from both SDKs
    func refreshSyncState() async {
        // Get Core sync progress
        // Sync progress tracking moved to WalletService to avoid duplication
        
        // Platform is always synced in current implementation
        isPlatformSynced = true
    }
    
    /// Create a funded identity (cross-layer operation)
    func createFundedIdentity(from wallet: Wallet, amount: UInt64) async throws -> Identity {
        return try await createFundedIdentityWithProgress(from: wallet, amount: amount, progressCallback: nil)
    }
    
    /// Create a funded identity with progress callbacks (enhanced version)
    func createFundedIdentityWithProgress(
        from wallet: Wallet,
        amount: UInt64,
        progressCallback: ((String) -> Void)?
    ) async throws -> Identity {
        guard let platformWrapper = platformWrapper,
              let assetLockBridge = assetLockBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            print("🚀 Starting funded identity creation process...")
            
            // Step 1: Create asset lock in Core with progress updates
            print("🔒 Creating asset lock transaction...")
            progressCallback?("broadcasting")
            
            let assetLock = try await assetLockBridge.fundIdentityWithRetry(
                from: wallet,
                amount: amount,
                maxRetries: 3
            )
            
            print("✅ Asset lock created: \(assetLock.transactionId)")
            
            // Step 2: Wait for InstantLock (already handled in fundIdentity)
            progressCallback?("instantlock")
            print("⏱️ InstantLock confirmed for transaction: \(assetLock.transactionId)")
            
            // Step 3: Create identity on Platform
            progressCallback?("identity")
            print("🆔 Creating Platform identity...")
            
            let identity = try await platformWrapper.createIdentity(
                with: assetLock
            )
            
            print("✅ Platform identity created: \(identity.id)")
            
            // Step 4: Update state
            identities.append(identity)
            
            // Step 5: Update balances
            let actualFee = assetLock.transaction.fee ?? 250_000 // Use actual fee or estimate
            updateCoreBalance(wallet.balance - amount - UInt64(actualFee))
            updatePlatformCredits(identity.balance)
            
            // Step 6: Sync identity data with persistence layer
            // Note: This would integrate with any identity storage/caching
            print("💾 Syncing identity data...")
            
            isLoading = false
            
            print("🎉 Identity creation completed successfully!")
            print("   Identity ID: \(identity.id)")
            print("   Balance: \(identity.balance) credits")
            print("   Transaction: \(assetLock.transactionId)")
            
            return identity
            
        } catch {
            print("🔴 Identity creation failed: \(error)")
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    /// Top up existing identity credits
    func topUpIdentity(_ identity: Identity, from wallet: Wallet, amount: UInt64) async throws {
        guard let platformWrapper = platformWrapper,
              let assetLockBridge = assetLockBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            // Create asset lock
            let assetLock = try await assetLockBridge.fundIdentity(
                from: wallet,
                amount: amount
            )
            
            // Top up identity
            let updatedIdentity = try await platformWrapper.topUpIdentity(
                identity,
                with: assetLock
            )
            
            // Update state
            if let index = identities.firstIndex(where: { $0.id == identity.id }) {
                identities[index] = updatedIdentity
            }
            
            updateCoreBalance(wallet.balance - amount)
            updatePlatformCredits(updatedIdentity.balance)
            
            isLoading = false
            
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    // MARK: - Enhanced Cross-Layer Operations
    
    /// Withdraw Platform credits back to Core wallet
    func withdrawCreditsToCore(
        from identity: Identity,
        to coreAddress: String,
        amount: UInt64
    ) async throws -> WithdrawResult {
        guard let crossLayerBridge = crossLayerBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            let result = try await crossLayerBridge.withdrawCreditsToCore(
                from: identity,
                to: coreAddress,
                amount: amount
            )
            
            // Update balances after withdrawal
            if result.status == .confirmed {
                updatePlatformCredits(identity.balance - amount)
                // Core balance would be updated by the transaction event
            }
            
            isLoading = false
            return result
            
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    /// Transfer between identities with backup funding
    func transferBetweenIdentities(
        from sourceIdentity: Identity,
        to targetIdentityId: String,
        amount: UInt64,
        useBackupFunding: Bool = false,
        backupWallet: Wallet? = nil
    ) async throws -> TransferResult {
        guard let crossLayerBridge = crossLayerBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            var backupConfig: BackupFundingConfig? = nil
            
            if useBackupFunding, let wallet = backupWallet {
                backupConfig = BackupFundingConfig(
                    sourceWallet: wallet,
                    fundingAmount: amount + 100_000 // Add buffer for fees
                )
            }
            
            let result = try await crossLayerBridge.transferBetweenIdentities(
                from: sourceIdentity,
                to: targetIdentityId,
                amount: amount,
                backupFunding: backupConfig
            )
            
            isLoading = false
            return result
            
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    /// Batch fund multiple identities
    func batchFundIdentities(
        from wallet: Wallet,
        operations: [BatchFundingOperation]
    ) async throws -> [FundingResult] {
        guard let crossLayerBridge = crossLayerBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            let results = try await crossLayerBridge.batchFundIdentities(
                from: wallet,
                operations: operations
            )
            
            // Update balances for successful operations
            let totalFunded = results.reduce(0) { sum, result in
                sum + result.amountFunded
            }
            updateCoreBalance(wallet.balance - totalFunded)
            
            isLoading = false
            return results
            
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    /// Synchronize all balances across layers
    func synchronizeAllBalances() async throws -> BalanceSyncResult {
        guard let crossLayerBridge = crossLayerBridge else {
            throw PlatformError.sdkInitializationFailed
        }
        
        isLoading = true
        error = nil
        
        do {
            let wallet = wallets.first ?? Wallet(id: "default", balance: 0, address: "")
            let result = try await crossLayerBridge.synchronizeBalances(
                for: wallet,
                identities: identities
            )
            
            // Update local state with synchronized balances
            updateCoreBalance(result.coreBalance)
            
            // Update platform balances
            for (identityId, balance) in result.platformBalances {
                if let index = identities.firstIndex(where: { $0.id == identityId }) {
                    identities[index] = Identity(
                        id: identityId,
                        balance: balance,
                        revision: identities[index].revision
                    )
                }
            }
            
            // Update price data
            await refreshPriceData()
            
            isLoading = false
            return result
            
        } catch {
            self.error = error
            isLoading = false
            throw error
        }
    }
    
    /// Get unified transaction history
    func getTransactionHistory() -> UnifiedTransactionHistoryService? {
        return transactionHistory
    }
    
    /// Refresh all data (balances, transactions, prices)
    func refreshAllData() async {
        await withTaskGroup(of: Void.self) { group in
            // Refresh sync state
            group.addTask {
                await self.refreshSyncState()
            }
            
            // Refresh price data
            group.addTask {
                await self.refreshPriceData()
            }
            
            // Refresh transaction history
            if let transactionHistory = self.transactionHistory {
                group.addTask {
                    await transactionHistory.refreshAllTransactions()
                }
            }
            
            // Synchronize balances
            group.addTask {
                do {
                    _ = try await self.synchronizeAllBalances()
                } catch {
                    print("⚠️ Failed to synchronize balances: \(error)")
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Subscribe to Core SDK events
        if let coreSDK = coreSDK as? DashSDK {
            coreSDK.eventPublisher
                .sink { [weak self] event in
                    self?.handleCoreEvent(event)
                }
                .store(in: &cancellables)
        }
        
        // Subscribe to balance changes
        $unifiedBalance
            .sink { [weak self] balance in
                self?.calculateUnifiedTotal(balance)
            }
            .store(in: &cancellables)
    }
    
    private func handleCoreEvent(_ event: SPVEvent) {
        Task { @MainActor in
            switch event {
            case .connectionStatusChanged(let connected):
                print("🌐 Connection status: \(connected ? "Connected" : "Disconnected")")
                
            case .blockReceived(let height, let hash):
                print("📦 Block received: \(height) - \(hash)")
                
            case .syncProgressUpdated(let progress):
                // DetailedSyncProgress can't be created directly - it has internal initializer
                // For now, we'll just log the progress
                print("🔄 Sync progress updated: \(progress.progress * 100)%")
                print("   Current: \(progress.currentHeight) / Total: \(progress.totalHeight)")
                
            case .balanceUpdated(let balance):
                print("💰 Balance updated: \(balance.total) satoshis")
                self.unifiedBalance.coreBalance = balance.total
                
                // Send local notification for sync completion
                Task {
                    // Check if we can access LocalNotificationService
                    // For now, just log that sync completed
                    print("🔔 Sync completed - would send notification")
                }
                
            case .error(let error):
                print("🔴 SPV Error: \(error)")
                self.error = error
                
            case .transactionReceived(let txid, let confirmed, let amount, let addresses, let blockHeight):
                print("💰 Transaction received:")
                print("   TXID: \(txid)")
                print("   Amount: \(amount) satoshis")
                print("   Confirmed: \(confirmed)")
                print("   Addresses: \(addresses)")
                if let height = blockHeight {
                    print("   Block: \(height)")
                }
                
            case .mempoolTransactionAdded(let txid, let amount, let addresses):
                print("🏊 Mempool transaction added: \(txid)")
                
            case .mempoolTransactionConfirmed(let txid, let blockHeight, let confirmations):
                print("✅ Mempool transaction confirmed: \(txid) at height \(blockHeight)")
                
            case .mempoolTransactionRemoved(let txid, let reason):
                print("🗑️ Mempool transaction removed: \(txid) - \(reason)")
            }
        }
    }
    
    private func calculateUnifiedTotal(_ balance: UnifiedBalance) {
        // Total is calculated in the UnifiedBalance struct
        // This method can be used for additional processing
    }
}

// MARK: - Models

struct UnifiedBalance {
    var coreBalance: UInt64 = 0
    var platformCredits: UInt64 = 0
    var tokenBalances: [String: TokenBalance] = [:]
    var priceData: PriceData = PriceData()
    
    /// Total balance in DASH (Core + tokens, not Platform credits)
    var totalInDash: Double {
        let coreDash = Double(coreBalance) / 100_000_000
        let tokenDash = tokenBalances.values.reduce(0) { sum, tokenBalance in
            sum + tokenBalance.dashValue
        }
        return coreDash + tokenDash
    }
    
    /// Total portfolio value in USD
    var totalInUSD: Double {
        return totalInDash * priceData.dashPriceUSD
    }
    
    /// Portfolio percentage breakdown
    var portfolioBreakdown: PortfolioBreakdown {
        let totalValue = totalInUSD
        guard totalValue > 0 else {
            return PortfolioBreakdown(corePercentage: 0, platformPercentage: 0, tokensPercentage: 0)
        }
        
        let coreValueUSD = (Double(coreBalance) / 100_000_000) * priceData.dashPriceUSD
        let tokenValueUSD = tokenBalances.values.reduce(0) { sum, tokenBalance in
            sum + tokenBalance.usdValue
        }
        // Platform credits don't have direct USD value but could be estimated based on utility
        let platformValueUSD = Double(platformCredits) * priceData.creditToUSDRate
        
        return PortfolioBreakdown(
            corePercentage: (coreValueUSD / totalValue) * 100,
            platformPercentage: (platformValueUSD / totalValue) * 100,
            tokensPercentage: (tokenValueUSD / totalValue) * 100
        )
    }
    
    /// 24h portfolio change
    var portfolioChange24h: PortfolioChange {
        let currentValue = totalInUSD
        let previousValue = totalInDash * priceData.dashPriceUSD24hAgo
        let changeUSD = currentValue - previousValue
        let changePercent = previousValue > 0 ? (changeUSD / previousValue) * 100 : 0
        
        return PortfolioChange(
            changeUSD: changeUSD,
            changePercent: changePercent,
            isPositive: changeUSD >= 0
        )
    }
    
    /// Formatted total for display
    var formattedTotal: String {
        String(format: "%.8g DASH", totalInDash)
    }
    
    /// Formatted total in USD
    var formattedTotalUSD: String {
        String(format: "$%.2f", totalInUSD)
    }
    
    /// Formatted Platform credits
    var formattedCredits: String {
        String(format: "%llu credits", platformCredits)
    }
    
    /// Formatted credits in USD equivalent
    var formattedCreditsUSD: String {
        let usdValue = Double(platformCredits) * priceData.creditToUSDRate
        return String(format: "$%.4f", usdValue)
    }
    
    /// Core balance in DASH
    var coreBalanceInDash: Double {
        return Double(coreBalance) / 100_000_000
    }
    
    /// Formatted core balance
    var formattedCoreBalance: String {
        String(format: "%.8g DASH", coreBalanceInDash)
    }
    
    /// Formatted core balance in USD
    var formattedCoreBalanceUSD: String {
        let usdValue = coreBalanceInDash * priceData.dashPriceUSD
        return String(format: "$%.2f", usdValue)
    }
}

// MARK: - Supporting Models

struct TokenBalance {
    let tokenId: String
    let balance: UInt64
    let symbol: String
    let name: String
    let decimals: Int
    let contractId: String
    let dashValue: Double // Current value in DASH
    let usdValue: Double // Current value in USD
    let pricePerToken: Double // Price per token in USD
    let change24h: Double // 24h price change percentage
    
    var formattedBalance: String {
        let divisor = pow(10.0, Double(decimals))
        let displayBalance = Double(balance) / divisor
        return String(format: "%.6g %@", displayBalance, symbol)
    }
    
    var formattedUSDValue: String {
        return String(format: "$%.4f", usdValue)
    }
}

struct PriceData {
    var dashPriceUSD: Double = 50.0 // Current DASH price in USD
    var dashPriceUSD24hAgo: Double = 49.5 // DASH price 24h ago
    var creditToUSDRate: Double = 0.000001 // Platform credits to USD rate
    var lastUpdated: Date = Date()
    
    var dashChange24h: Double {
        guard dashPriceUSD24hAgo > 0 else { return 0 }
        return ((dashPriceUSD - dashPriceUSD24hAgo) / dashPriceUSD24hAgo) * 100
    }
    
    var formattedDashPrice: String {
        return String(format: "$%.2f", dashPriceUSD)
    }
    
    var formattedDashChange: String {
        let sign = dashChange24h >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", dashChange24h))%"
    }
}

struct PortfolioBreakdown {
    let corePercentage: Double
    let platformPercentage: Double
    let tokensPercentage: Double
    
    var formattedCore: String {
        return String(format: "%.1f%%", corePercentage)
    }
    
    var formattedPlatform: String {
        return String(format: "%.1f%%", platformPercentage)
    }
    
    var formattedTokens: String {
        return String(format: "%.1f%%", tokensPercentage)
    }
}

struct PortfolioChange {
    let changeUSD: Double
    let changePercent: Double
    let isPositive: Bool
    
    var formattedChangeUSD: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)$\(String(format: "%.2f", abs(changeUSD)))"
    }
    
    var formattedChangePercent: String {
        let sign = isPositive ? "+" : ""
        return "\(sign)\(String(format: "%.2f", abs(changePercent)))%"
    }
    
    var color: String {
        return isPositive ? "green" : "red"
    }
}

// MARK: - Connection State

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// Platform wrapper extension removed - implementation is in PlatformSDKWrapper.swift

// Mock Core SDK Extension removed - DashSDK already has these properties