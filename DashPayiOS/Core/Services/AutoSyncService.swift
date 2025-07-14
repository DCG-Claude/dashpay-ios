import Foundation
import Combine
import SwiftData
import os.log

/// Service responsible for managing auto-sync functionality
@MainActor
class AutoSyncService: ObservableObject {
    @Published var autoSyncEnabled = true
    @Published var lastAutoSyncDate: Date?
    @Published var syncQueue: [HDWallet] = []
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "AutoSyncService")
    private var autoSyncTimer: Timer?
    private weak var modelContext: ModelContext?
    
    /// Configure the service with model context
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("🔧 AutoSyncService configured with modelContext")
    }
    
    /// Start periodic auto-sync
    func startPeriodicSync(syncHandler: @escaping () async -> Void) {
        logger.info("⏰ Starting periodic auto-sync")
        // Cancel existing timer
        autoSyncTimer?.invalidate()
        
        // Setup new timer for every 30 minutes
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task {
                await syncHandler()
            }
        }
    }
    
    /// Stop periodic auto-sync
    func stopPeriodicSync() {
        logger.info("⏸️ Stopping periodic auto-sync")
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
    
    /// Check if wallet should be synced
    func shouldSync(_ wallet: HDWallet, isCurrentlySyncing: Bool, networkMonitor: NetworkMonitor?) -> Bool {
        // Don't sync if already syncing
        if isCurrentlySyncing {
            return false
        }
        
        // Always sync if never synced before
        if wallet.lastSynced == nil {
            logger.info("🆕 Wallet never synced before - MUST SYNC")
            
            // Check network connectivity
            let isNetworkConnected = networkMonitor?.isConnected ?? true
            if !isNetworkConnected {
                logger.warning("📵 No network connectivity - cannot sync")
                return false
            }
            
            return true
        }
        
        // Don't sync if synced recently
        let timeSinceLastSync = Date().timeIntervalSince(wallet.lastSynced!)
        if timeSinceLastSync < 300 { // 5 minutes
            logger.info("⏰ Wallet synced recently (\(Int(timeSinceLastSync))s ago) - skipping")
            return false
        }
        
        // Check network connectivity
        let isNetworkConnected = networkMonitor?.isConnected ?? true
        if !isNetworkConnected {
            logger.warning("📵 No network connectivity - cannot sync")
            return false
        }
        
        logger.info("✅ Sync is needed for wallet (last sync: \(Int(timeSinceLastSync))s ago)")
        return true
    }
    
    /// Get wallets that need sync
    func getWalletsNeedingSync() -> [HDWallet] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<HDWallet>()
        let allWallets = (try? context.fetch(descriptor)) ?? []
        
        return allWallets.filter { wallet in
            // Check if wallet has been synced recently
            if let lastSync = wallet.lastSynced,
               Date().timeIntervalSince(lastSync) < 300 { // 5 minutes
                return false
            }
            return true
        }
    }
    
    /// Update last auto-sync date
    func updateLastAutoSyncDate(_ date: Date) {
        lastAutoSyncDate = date
        logger.info("📅 Updated last auto-sync date: \(date)")
    }
    
    /// Add wallet to sync queue
    func addToSyncQueue(_ wallet: HDWallet) {
        if !syncQueue.contains(where: { $0.id == wallet.id }) {
            syncQueue.append(wallet)
            logger.info("📋 Added wallet to sync queue: \(wallet.name)")
        }
    }
    
    /// Remove wallet from sync queue
    func removeFromSyncQueue(_ wallet: HDWallet) {
        syncQueue.removeAll { $0.id == wallet.id }
        logger.info("📋 Removed wallet from sync queue: \(wallet.name)")
    }
    
    /// Clear sync queue
    func clearSyncQueue() {
        syncQueue.removeAll()
        logger.info("📋 Cleared sync queue")
    }
    
    /// Reset auto-sync state
    func reset() {
        logger.info("🔄 Resetting auto-sync state")
        stopPeriodicSync()
        syncQueue.removeAll()
        lastAutoSyncDate = nil
    }
}