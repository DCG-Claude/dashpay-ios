import Foundation
import Combine
import os.log
import SwiftDashSDK
import SwiftDashCoreSDK

/// Service responsible for managing sync state and progress
@MainActor
class SyncStateService: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var syncProgress: SyncProgress?
    @Published var detailedSyncProgress: DetailedSyncProgress?
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "SyncStateService")
    private var activeSyncTask: Task<Void, Never>?
    private let syncLock = NSLock()
    private var syncRequestId: UUID?
    
    /// Computed property for sync statistics
    var syncStatistics: [String: String] {
        guard let progress = detailedSyncProgress else {
            return [:]
        }
        // Create statistics from available properties
        var stats: [String: String] = [:]
        stats["Current Height"] = "\(progress.currentHeight)"
        stats["Total Height"] = "\(progress.totalHeight)"
        stats["Progress"] = progress.formattedPercentage
        stats["Speed"] = progress.formattedSpeed
        stats["Stage"] = progress.stage.description
        stats["Connected Peers"] = "\(progress.connectedPeers)"
        if progress.estimatedSecondsRemaining > 0 {
            stats["ETA"] = progress.formattedTimeRemaining
        }
        return stats
    }
    
    /// Start sync operation
    func startSync(requestId: UUID) {
        logger.info("🔄 Starting sync (ID: \(requestId.uuidString.prefix(8)))")
        syncRequestId = requestId
        isSyncing = true
    }
    
    /// Update sync progress
    func updateProgress(_ progress: DetailedSyncProgress) {
        detailedSyncProgress = progress
        
        // Convert to legacy SyncProgress for compatibility
        syncProgress = SyncProgress(
            currentHeight: progress.currentHeight,
            totalHeight: progress.totalHeight,
            progress: progress.percentage / 100.0,
            status: mapSyncStageToStatus(progress.stage),
            estimatedTimeRemaining: progress.estimatedSecondsRemaining > 0 ? TimeInterval(progress.estimatedSecondsRemaining) : nil,
            message: progress.stageMessage
        )
    }
    
    /// Update sync progress (legacy compatibility)
    func updateProgress(_ progress: SyncProgress) {
        syncProgress = progress
    }
    
    /// Complete sync operation
    func completeSync() {
        logger.info("✅ Sync completed")
        isSyncing = false
        activeSyncTask = nil
    }
    
    /// Cancel active sync
    func cancelSync() {
        syncLock.lock()
        defer { syncLock.unlock() }
        
        if let task = activeSyncTask {
            logger.info("🛑 Cancelling active sync")
            task.cancel()
            activeSyncTask = nil
        }
        
        isSyncing = false
        syncRequestId = nil
    }
    
    /// Set active sync task
    func setActiveSyncTask(_ task: Task<Void, Never>) {
        activeSyncTask = task
    }
    
    /// Check if sync is currently active
    func hasActiveSync() -> Bool {
        return activeSyncTask?.isCancelled == false
    }
    
    /// Get current sync request ID
    func getCurrentSyncRequestId() -> UUID? {
        return syncRequestId
    }
    
    /// Set sync progress directly (for legacy compatibility)
    func setSyncProgress(_ progress: SyncProgress) {
        syncProgress = progress
    }
    
    /// Reset sync state
    func reset() {
        logger.info("🔄 Resetting sync state")
        cancelSync()
        syncProgress = nil
        detailedSyncProgress = nil
    }
    
    // Helper to map sync stage to legacy status
    private func mapSyncStageToStatus(_ stage: SyncStage) -> SwiftDashCoreSDK.SyncStatus {
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
}