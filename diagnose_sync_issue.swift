import Foundation
import SwiftDashCoreSDK
import DashSPVFFI

/*
 * Diagnostic tool to identify why sync shows 0 connected peers despite logs showing connections
 * 
 * Key findings:
 * 1. SPVClient DOES set up event callbacks properly (lines 714-717 in SPVClient.swift)
 * 2. SPVClient DOES wait for peer connections (lines 742-770 in SPVClient.swift) 
 * 3. But stats show 0 connected peers while logs show successful connections
 * 
 * This suggests the issue is in the FFI layer or how stats are being reported
 */

class SyncDiagnostics {
    
    static func diagnoseConnectionIssue(client: SPVClient) async {
        print("\n🔍 === SYNC DIAGNOSTICS ===")
        print("Time: \(Date())")
        
        // 1. Check basic client state
        print("\n1️⃣ Client State:")
        print("   - Is Connected: \(client.isConnected)")
        print("   - Has FFI Client: \(client.ffiClient != nil)")
        
        // 2. Get stats multiple ways
        print("\n2️⃣ Stats Comparison:")
        
        // Method A: Via SPVClient stats property
        await client.updateStats()
        if let stats = client.stats {
            print("   Via SPVClient.stats:")
            print("     - Connected peers: \(stats.connectedPeers)")
            print("     - Total peers: \(stats.totalPeers)")
            print("     - Header height: \(stats.headerHeight)")
        }
        
        // Method B: Direct FFI call
        if let ffiClient = client.ffiClient {
            if let ffiStats = dash_spv_ffi_client_get_stats(ffiClient) {
                defer { dash_spv_ffi_spv_stats_destroy(ffiStats) }
                let stats = ffiStats.pointee
                print("   Via Direct FFI:")
                print("     - connected_peers: \(stats.connected_peers)")
                print("     - total_peers: \(stats.total_peers)")
                print("     - header_height: \(stats.header_height)")
                print("     - bytes_received: \(stats.bytes_received)")
            }
        }
        
        // 3. Check event callbacks
        print("\n3️⃣ Event Callbacks:")
        print("   - Callbacks set: \(client.eventCallbacksSet)")
        
        // 4. Network diagnostics
        print("\n4️⃣ Network Configuration:")
        print("   - Network: \(client.configuration.network.rawValue)")
        print("   - Peers: \(client.configuration.additionalPeers.joined(separator: ", "))")
        print("   - Max peers: \(client.configuration.maxPeers)")
        
        // 5. Timing analysis
        print("\n5️⃣ Timing Analysis:")
        print("   Checking stats over 5 seconds...")
        
        for i in 0..<5 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await client.updateStats()
            if let stats = client.stats {
                print("   [\(i+1)s] Peers: \(stats.connectedPeers), Headers: \(stats.headerHeight)")
            }
        }
        
        print("\n=== END DIAGNOSTICS ===\n")
    }
    
    static func compareLogs(rustLogs: String, ffiStats: String) {
        print("\n📊 Log vs Stats Comparison:")
        
        // Extract peer info from Rust logs
        let peerPattern = #"Peer (\d+\.\d+\.\d+\.\d+:\d+) sent SendHeaders2"#
        let regex = try? NSRegularExpression(pattern: peerPattern)
        let matches = regex?.matches(in: rustLogs, range: NSRange(rustLogs.startIndex..., in: rustLogs)) ?? []
        
        let connectedPeers = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: rustLogs) else { return nil }
            return String(rustLogs[range])
        }
        
        print("   Peers from logs: \(connectedPeers.count)")
        for peer in connectedPeers {
            print("     - \(peer)")
        }
        
        // Extract stats
        if ffiStats.contains("connected_peers: 0") {
            print("   ⚠️ FFI stats show 0 peers despite \(connectedPeers.count) peers in logs!")
            print("   This confirms a disconnect between Rust layer and FFI stats")
        }
    }
}

// Potential root causes and fixes:

/*
 * ROOT CAUSE ANALYSIS:
 * 
 * The issue appears to be that the Rust SPV implementation successfully connects to peers
 * (as shown in logs), but the FFI stats structure doesn't reflect these connections.
 * 
 * Possible causes:
 * 
 * 1. **Stats Update Timing**: The stats might be queried before the peer manager updates them
 *    Fix: Add delay or polling mechanism
 * 
 * 2. **Different Connection Pools**: The Rust layer might track connections differently than FFI stats
 *    Fix: Ensure FFI stats query the same connection pool
 * 
 * 3. **FFI Struct Initialization**: The FFI stats struct might not be properly initialized
 *    Fix: Check FFI bridge code for proper memory management
 * 
 * 4. **Thread Safety**: Stats might be accessed from different thread than peer connections
 *    Fix: Ensure thread-safe access to peer count
 * 
 * 5. **Event Callback Requirement**: Some FFI implementations require callbacks to update stats
 *    Fix: Ensure all required callbacks are set (already done in SPVClient)
 */

// Immediate workaround:
extension WalletService {
    
    /// Workaround: Bypass stats check and proceed with sync if logs show connections
    func startSyncRegardlessOfStats() async throws {
        guard let client = spvClient, isConnected else {
            throw WalletError.notConnected
        }
        
        logger.info("🔄 Starting sync (bypassing peer stats check)...")
        logger.warning("⚠️ Stats show 0 peers but proceeding based on connection logs")
        
        // Give connections a moment to stabilize
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Start sync without checking stats
        try await startSyncWithCallbacks()
    }
}

/*
 * RECOMMENDED FIX:
 * 
 * The issue is likely in the rust-dashcore FFI layer where stats are collected.
 * The peer connections are established but not reflected in the stats structure.
 * 
 * Short-term: Use the workaround above to proceed with sync
 * Long-term: Fix the FFI stats collection in rust-dashcore
 */