import Foundation
import SwiftDashCoreSDK
import SwiftData
import os.log

/// Service responsible for wallet sync operations and progress tracking
@MainActor
class WalletSyncService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletSyncService")
    
    @Published var isSyncing: Bool = false
    @Published var syncProgress: SyncProgress?
    @Published var detailedSyncProgress: SwiftDashCoreSDK.DetailedSyncProgress?
    
    private let syncService = SyncStateService()
    private var modelContext: ModelContext?
    
    // Computed property for sync statistics
    var syncStatistics: [String: String] {
        return syncService.syncStatistics
    }
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupSyncStateBindings()
    }
    
    /// Setup bindings between WalletSyncService @Published properties and SyncStateService
    private func setupSyncStateBindings() {
        // Bind syncService properties to WalletSyncService @Published properties
        syncService.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)
        
        syncService.$syncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$syncProgress)
        
        syncService.$detailedSyncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$detailedSyncProgress)
    }
    
    func startSync(sdk: DashSDK, activeWallet: HDWallet?) async throws {
        guard sdk.isConnected else {
            throw WalletError.notConnected
        }
        
        // Check if sync is already in progress
        if syncService.hasActiveSync() {
            logger.warning("⚠️ Sync already in progress, skipping duplicate request")
            return
        }
        
        // Generate new sync request ID
        let requestId = UUID()
        syncService.startSync(requestId: requestId)
        
        let syncTask = Task { [weak self, requestId] in
            do {
                logger.info("📡 Starting enhanced sync with detailed progress...")
                var lastLogTime = Date()
                
                // Use the new sync progress stream from SDK
                for await progress in sdk.syncProgressStream() {
                    // Check if this sync was cancelled by a newer sync
                    guard self?.syncService.getCurrentSyncRequestId() == requestId else {
                        logger.info("🛑 Sync cancelled (newer sync started)")
                        break
                    }
                    
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        // Use the SDK progress directly
                        self?.syncService.updateProgress(progress)
                    }
                    
                    // Log progress every second to avoid spam
                    if Date().timeIntervalSince(lastLogTime) > 1.0 {
                        print("\(progress.stage.icon) \(progress.statusMessage)")
                        print("   Speed: \(progress.formattedSpeed) | ETA: \(progress.formattedTimeRemaining)")
                        print("   Peers: \(progress.connectedPeers) | Headers: \(progress.totalHeadersProcessed)")
                        lastLogTime = Date()
                    }
                    
                    // Update sync state in storage
                    if let wallet = activeWallet, let syncProgress = self?.syncProgress {
                        await self?.updateSyncState(walletId: wallet.id, progress: syncProgress)
                    }
                    
                    // Check if sync is complete
                    if progress.isComplete {
                        break
                    }
                }
                
                // Sync completed
                await MainActor.run {
                    logger.info("✅ Sync completed (ID: \(requestId.uuidString.prefix(8)))")
                    self?.syncService.completeSync()
                    
                    if let wallet = activeWallet {
                        wallet.lastSynced = Date()
                        try? self?.modelContext?.save()
                    }
                }
                
            } catch {
                await MainActor.run {
                    self?.syncService.reset()
                    self?.logger.error("❌ Sync error: \(error)")
                }
            }
        }
        
        syncService.setActiveSyncTask(syncTask)
    }
    
    // Alternative sync method using callbacks for real-time updates
    func startSyncWithCallbacks(sdk: DashSDK, activeWallet: HDWallet?) async throws {
        guard sdk.isConnected else {
            throw WalletError.notConnected
        }
        
        print("🔄 Starting callback-based sync for wallet: \(activeWallet?.name ?? "Unknown")")
        let requestId = UUID()
        syncService.startSync(requestId: requestId)
        
        try await sdk.syncToTipWithProgress(
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    // Use the SDK progress directly
                    self?.syncService.updateProgress(progress)
                    
                    print("\(progress.stage.icon) \(progress.statusMessage)")
                }
            },
            completionCallback: { [weak self] success, error in
                Task { @MainActor in
                    if success {
                        self?.syncService.completeSync()
                    } else {
                        self?.syncService.reset()
                    }
                    
                    if success {
                        print("✅ Sync completed successfully!")
                        if let wallet = activeWallet {
                            wallet.lastSynced = Date()
                            try? self?.modelContext?.save()
                        }
                    } else {
                        print("❌ Sync failed: \(error ?? "Unknown error")")
                    }
                }
            }
        )
    }
    
    func stopSync() {
        syncService.cancelSync()
    }
    
    func hasActiveSync() -> Bool {
        return syncService.hasActiveSync()
    }
    
    // Helper to map sync stage to legacy status
    private func mapSyncStageToStatus(_ stage: SyncStage) -> SyncStatus {
        switch stage {
        case .connecting:
            return .connecting
        case .queryingHeight:
            return .connecting
        case .downloading, .validating, .storing:
            return .downloadingHeaders
        case .complete:
            return .synced
        case .failed:
            return .error
        }
    }
    
    private func updateSyncState(walletId: UUID, progress: SyncProgress) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<SyncState>()
        let allStates = try? context.fetch(descriptor)
        
        if let syncState = allStates?.first(where: { $0.walletId == walletId }) {
            syncState.update(from: progress)
        } else {
            let syncState = SyncState(walletId: walletId)
            syncState.update(from: progress)
            context.insert(syncState)
        }
        
        try? context.save()
    }
    
    private func handleSyncProgressUpdated(_ progress: SyncProgress) {
        self.syncService.updateProgress(progress)
        logger.info("📊 Sync progress: \(progress.percentageComplete)% - \(progress.status.description)")
    }
    
    func reset() {
        syncService.reset()
    }
}