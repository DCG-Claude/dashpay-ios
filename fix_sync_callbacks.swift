import Foundation
import SwiftDashCoreSDK

// Fix for sync issue in dashpay-ios
// The problem: Event callbacks are set up correctly, but sync starts before peers are fully connected
// Solution: Add proper peer connection verification before starting sync

extension WalletService {
    
    /// Wait for peers to be connected before starting sync
    /// This ensures the SPV client has established connections before attempting to download headers
    func waitForPeerConnections(timeout: TimeInterval = 30) async throws {
        guard let client = spvClient, client.isConnected else {
            throw WalletError.notConnected
        }
        
        logger.info("⏳ Waiting for peer connections...")
        
        let startTime = Date()
        var lastPeerCount: UInt32 = 0
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Update stats to get current peer count
            await client.updateStats()
            
            if let stats = client.stats {
                if stats.connectedPeers > 0 {
                    logger.info("✅ Connected to \(stats.connectedPeers) peers")
                    
                    // Wait a bit more to ensure connections are stable
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Verify peers are still connected
                    await client.updateStats()
                    if let verifyStats = client.stats, verifyStats.connectedPeers > 0 {
                        logger.info("✅ Peer connections verified: \(verifyStats.connectedPeers) peers")
                        return
                    }
                }
                
                if stats.connectedPeers != lastPeerCount {
                    logger.info("   Peer count changed: \(lastPeerCount) → \(stats.connectedPeers)")
                    lastPeerCount = stats.connectedPeers
                }
            }
            
            // Wait before checking again
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        throw WalletError.connectionTimeout("Failed to connect to any peers within \(Int(timeout)) seconds")
    }
    
    /// Enhanced sync start that waits for peer connections
    func startSyncWithPeerVerification() async throws {
        guard let client = spvClient, isConnected else {
            throw WalletError.notConnected
        }
        
        logger.info("🔄 Starting enhanced sync with peer verification...")
        
        // Step 1: Wait for peer connections
        try await waitForPeerConnections()
        
        // Step 2: Now start the actual sync
        logger.info("🚀 Peers connected, starting sync...")
        try await startSyncWithCallbacks()
    }
}

// Update the connect method to ensure proper initialization
extension WalletService {
    
    /// Enhanced connection method that verifies peer connections
    func connectWithVerification(wallet: HDWallet, account: HDAccount) async throws {
        // First, do the normal connection
        try await connect(wallet: wallet, account: account)
        
        // Then verify we have peer connections
        try await waitForPeerConnections()
        
        logger.info("✅ Connection fully established with verified peers")
    }
}

// Fix for EnhancedSyncProgressView to use the enhanced sync method
extension EnhancedSyncProgressView {
    
    /// Modified startSync that ensures peers are connected first
    private func startSyncWithVerification() {
        hasStarted = true
        syncError = nil
        
        Task {
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds (increased)
                if hasStarted && walletService.syncProgress == nil && walletService.detailedSyncProgress == nil {
                    await MainActor.run {
                        syncError = "Sync timed out - no progress received after 30 seconds"
                        hasStarted = false
                    }
                }
            }
            
            do {
                print("📱 EnhancedSyncProgressView: Starting sync with peer verification...")
                
                // Use the enhanced sync method that waits for peers
                try await walletService.startSyncWithPeerVerification()
                
                print("✅ EnhancedSyncProgressView: Sync started successfully with verified peers")
                timeoutTask.cancel()
            } catch {
                print("❌ EnhancedSyncProgressView: Sync error: \(error)")
                timeoutTask.cancel()
                
                await MainActor.run {
                    syncError = "Sync failed: \(error.localizedDescription)"
                    hasStarted = false
                }
            }
        }
    }
}

// Additional debugging helper
extension SPVClient {
    
    /// Debug method to log detailed connection state
    func debugConnectionState() async {
        print("\n🔍 SPV Client Debug State:")
        print("   Is Connected: \(isConnected)")
        print("   Event Callbacks Set: \(eventCallbacksSet)")
        
        await updateStats()
        
        if let stats = stats {
            print("   Connected Peers: \(stats.connectedPeers)")
            print("   Total Peers: \(stats.totalPeers)")
            print("   Header Height: \(stats.headerHeight)")
            print("   Filter Height: \(stats.filterHeight)")
            print("   Headers Downloaded: \(stats.headersDownloaded)")
            print("   Bytes Received: \(stats.bytesReceived)")
        } else {
            print("   Stats: Not available")
        }
        
        // Check if we can get stats via FFI directly
        if let client = ffiClient {
            if let ffiStats = dash_spv_ffi_client_get_stats(client) {
                defer { dash_spv_ffi_spv_stats_destroy(ffiStats) }
                let stats = ffiStats.pointee
                print("\n   FFI Direct Stats:")
                print("   - connected_peers: \(stats.connected_peers)")
                print("   - total_peers: \(stats.total_peers)")
                print("   - header_height: \(stats.header_height)")
            }
        }
        
        print("\n")
    }
}

/*
 * Summary of fixes:
 * 
 * 1. The main issue is that sync starts before peers are fully connected
 * 2. Event callbacks ARE being set up correctly by SPVClient
 * 3. The "0 connected peers" happens because sync checks stats too early
 * 4. Solution: Add waitForPeerConnections() method that polls until peers connect
 * 5. Use startSyncWithPeerVerification() instead of startSync()
 * 
 * To implement:
 * 1. Add these extension methods to WalletService
 * 2. Update EnhancedSyncProgressView to call startSyncWithVerification
 * 3. Optionally update connection flow to use connectWithVerification
 */