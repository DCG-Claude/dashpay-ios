# DashPay iOS Sync Issue Analysis

## Problem Summary
The DashPay iOS app shows "0 connected peers" in FFI stats despite logs showing successful peer connections, preventing sync from starting.

## Key Differences Between Working Example and DashPay iOS

### 1. ✅ Event Callbacks (NOT the issue)
- **rust-dashcore example**: Sets comprehensive callbacks
- **dashpay-ios**: ALSO sets comprehensive callbacks via SPVClient
- **Analysis**: Both implementations properly set event callbacks. This is NOT the issue.

### 2. ✅ Connection Waiting (NOT the issue)  
- **rust-dashcore example**: SPVClient waits up to 30s for peers
- **dashpay-ios**: Uses the same SPVClient, so ALSO waits for peers
- **Analysis**: Both wait for connections. This is NOT the issue.

### 3. ❌ FFI Stats Reporting (THE ISSUE)
- **rust-dashcore example**: Stats correctly reflect connected peers
- **dashpay-ios**: Stats show 0 peers despite active connections
- **Analysis**: This is a bug in the FFI layer stats collection

### 4. ⚠️ Sync Initiation Flow
- **rust-dashcore example**: Likely starts sync automatically after connection
- **dashpay-ios**: Requires manual sync button click after connection
- **Analysis**: Minor UX difference, not the root cause

### 5. ✅ Network Configuration
- **rust-dashcore example**: Uses same hardcoded peers
- **dashpay-ios**: Uses identical peer list
- **Analysis**: Network config is identical. This is NOT the issue.

## Root Cause
The FFI stats structure (`dash_spv_ffi_client_get_stats`) returns 0 for `connected_peers` even though the Rust SPV layer has successfully connected to peers. This prevents sync from starting because the sync logic checks stats before proceeding.

## Evidence
```
// Rust logs show successful connections:
2025-07-01T15:53:10.272780Z  INFO Peer 34.220.243.24:19999 sent SendHeaders2
2025-07-01T15:53:10.273075Z  INFO Peer 54.149.33.167:19999 sent SendHeaders2

// But FFI stats show:
🔍 FFI Stats Debug:
   - connected_peers: 0
   - total_peers: 0
   - header_height: 0
```

## Recommended Fixes

### 1. Immediate Workaround (for dashpay-ios)
```swift
// In WalletService.swift, modify startSync to bypass stats check:
func startSyncWithWorkaround() async throws {
    guard isConnected else { throw WalletError.notConnected }
    
    // Wait briefly for connections to stabilize
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    
    // Log warning but proceed
    logger.warning("⚠️ Proceeding with sync despite stats showing 0 peers")
    
    // Start sync without checking peer count
    try await startSyncWithCallbacks()
}
```

### 2. Proper Fix (for rust-dashcore)
The issue is in the FFI bridge where `dash_spv_ffi_client_get_stats` collects statistics. The peer connection count is not being properly propagated from the Rust SPV implementation to the FFI stats structure.

Likely locations to check in rust-dashcore:
- `dash-spv-ffi/src/client.rs` - How stats are collected
- `dash-spv/src/peer_manager.rs` - How peer count is tracked
- Thread synchronization between peer management and stats collection

### 3. Alternative Approach
Instead of relying on FFI stats, check for peer connections by:
- Monitoring for block/header events (indicates active peers)
- Checking if bytes_received increases over time
- Using connection logs as truth source

## Conclusion
This is NOT an issue with event callbacks or connection setup in dashpay-ios. The app correctly uses the SwiftDashCoreSDK which properly configures everything. The issue is a bug in the FFI stats reporting layer that needs to be fixed in rust-dashcore.