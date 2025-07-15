# DashPay iOS Sync Connection Failure - Debugging Plan

## Issue Summary
The DashPay iOS app shows "Disconnected" and sync is not working. This debugging plan provides a systematic approach to identify and fix the connection issues.

## Current State Analysis

### Architecture Overview
1. **SDK Stack**:
   - `DashSDK` - Main SDK interface
   - `SPVClient` - Handles SPV connection and sync
   - `FFIBridge` - Bridges Swift to Rust FFI
   - `FFIInitializer` - Manages FFI library initialization
   - `ConnectionDiagnostics` - Provides connection debugging tools

2. **Key Components**:
   - FFI Libraries: `libdash_spv_ffi`, `librs_sdk_ffi`
   - Network Configuration: Testnet/Mainnet peers
   - Sync Progress tracking
   - Event callbacks for real-time updates

## Debugging Steps

### 1. SDK Initialization Issues

#### 1.1 FFI Library Loading
**Problem**: FFI libraries may not be loading correctly

**Debug Steps**:
```swift
// Add to DashSDK.init()
print("🔵 FFI Manager Diagnostics:")
print(FFIManager.shared.diagnostics())

// Check FFI version
if let versionPtr = dash_spv_ffi_version() {
    print("✅ FFI Version: \(String(cString: versionPtr))")
} else {
    print("🔴 FFI library not loaded!")
}
```

**Common Issues**:
- Missing `-force_load` flag in build settings
- Wrong library architecture (simulator vs device)
- Symbol conflicts between libraries

#### 1.2 FFI Initialization Failures
**Add enhanced error logging**:
```swift
// In FFIInitializer.initializeWithTimeout()
if initResult != 0 {
    print("🔴 FFI init failed with code: \(initResult)")
    print("🔴 errno: \(errno)")
    print("🔴 strerror: \(String(cString: strerror(errno)))")
}
```

### 2. Network Connectivity Problems

#### 2.1 System Network Check
**Add network diagnostics**:
```swift
// Add to SPVClient.connect()
let monitor = NetworkMonitor()
print("📡 Network Status:")
print("  - Connected: \(monitor.isConnected)")
print("  - Type: \(monitor.connectionType?.description ?? "Unknown")")
```

#### 2.2 Peer Connectivity
**Test peer connections**:
```swift
// Add peer connectivity test
public func testPeerConnections() async {
    print("🔍 Testing peer connectivity...")
    let results = await testPeerConnectivity()
    for result in results {
        print(result.summary)
    }
}
```

#### 2.3 DNS Resolution
**Check DNS seeds**:
```swift
// Add DNS resolution test
let testnetSeeds = [
    "testnet-seed.dash.org",
    "testnet.dnsseed.dash.org"
]

for seed in testnetSeeds {
    let resolved = await canResolveHost(seed)
    print("DNS \(seed): \(resolved ? "✅" : "❌")")
}
```

### 3. Error Logging Improvements

#### 3.1 Add Comprehensive Logging
```swift
// Create debug logging helper
public class SyncDebugLogger {
    static func logConnectionAttempt(_ attempt: Int, maxAttempts: Int) {
        print("🔄 Connection attempt \(attempt)/\(maxAttempts)")
        print("  - Timestamp: \(Date())")
        print("  - Thread: \(Thread.current)")
        print("  - FFI Initialized: \(FFIInitializer.initialized)")
    }
    
    static func logConnectionError(_ error: Error, context: String) {
        print("🔴 Connection Error in \(context):")
        print("  - Error: \(error)")
        print("  - Type: \(type(of: error))")
        
        if let sdkError = error as? DashSDKError {
            print("  - Recovery: \(sdkError.recoverySuggestion ?? "None")")
        }
        
        // Log FFI error if available
        if let ffiError = FFIBridge.getLastError() {
            print("  - FFI Error: \(ffiError)")
        }
    }
    
    static func logSyncProgress(_ progress: DetailedSyncProgress) {
        print("📊 Sync Progress:")
        print("  - Height: \(progress.currentHeight)/\(progress.totalHeight)")
        print("  - Progress: \(progress.formattedPercentage)")
        print("  - Speed: \(progress.formattedSpeed)")
        print("  - Stage: \(progress.stage.description)")
        print("  - Peers: \(progress.connectedPeers)")
    }
}
```

#### 3.2 Add Connection State Tracking
```swift
// Add to SPVClient
private var connectionStateHistory: [(Date, String)] = []

private func logConnectionState(_ state: String) {
    let entry = (Date(), state)
    connectionStateHistory.append(entry)
    
    // Keep last 100 entries
    if connectionStateHistory.count > 100 {
        connectionStateHistory.removeFirst()
    }
    
    print("🔸 Connection State: \(state)")
}
```

### 4. Connection Debugging Steps

#### 4.1 Create Connection Test Suite
```swift
public class ConnectionDebugger {
    public static func runFullDiagnostics(for sdk: DashSDK) async {
        print("\n=== DashPay Connection Diagnostics ===")
        print("Timestamp: \(Date())\n")
        
        // 1. Check FFI
        print("1. FFI Status:")
        print(FFIManager.shared.diagnostics())
        
        // 2. Check Network
        print("\n2. Network Status:")
        let networkDiag = await ConnectionDiagnostics.runDiagnostics(for: sdk.spvClient)
        print(networkDiag.summary)
        
        // 3. Check Configuration
        print("\n3. Configuration:")
        print("  - Network: \(sdk.spvClient.configuration.network.name)")
        print("  - Peers: \(sdk.spvClient.configuration.additionalPeers)")
        print("  - Data Dir: \(sdk.spvClient.configuration.dataDirectory?.path ?? "None")")
        
        // 4. Connection attempt with detailed logging
        print("\n4. Connection Test:")
        do {
            try await sdk.connect()
            print("✅ Connection successful!")
        } catch {
            print("🔴 Connection failed: \(error)")
        }
        
        // 5. Get sync diagnostics
        print("\n5. Sync Diagnostics:")
        print(sdk.spvClient.getSyncDiagnostics())
    }
}
```

#### 4.2 Add Connection Retry with Backoff
```swift
// Enhanced connection with exponential backoff
public func connectWithEnhancedRetry() async throws {
    let maxRetries = 5
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            // Log attempt
            SyncDebugLogger.logConnectionAttempt(attempt, maxAttempts: maxRetries)
            
            // Clear any previous FFI errors
            dash_spv_ffi_clear_error()
            
            // Try to connect
            try await connect()
            
            // Success - verify connection
            if isConnected && peers > 0 {
                print("✅ Connected with \(peers) peers")
                return
            } else {
                throw DashSDKError.connectionFailed("Connected but no peers")
            }
            
        } catch {
            lastError = error
            SyncDebugLogger.logConnectionError(error, context: "Attempt \(attempt)")
            
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt - 1))
                print("⏳ Waiting \(delay)s before retry...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    throw lastError ?? DashSDKError.connectionFailed("Max retries exceeded")
}
```

### 5. Common Issues and Solutions

#### 5.1 FFI Not Initialized
**Symptoms**: 
- `dash_spv_ffi_version()` returns nil
- "FFI library not loaded" errors

**Solutions**:
1. Check build settings for `-force_load` flags
2. Verify library paths in build phases
3. Check for architecture mismatches

#### 5.2 Network Unreachable
**Symptoms**:
- "No peers connected" after timeout
- DNS resolution failures

**Solutions**:
1. Test with hardcoded IP addresses
2. Check firewall/VPN settings
3. Verify network permissions in Info.plist

#### 5.3 Sync Stuck at 0%
**Symptoms**:
- Connection successful but sync doesn't progress
- No sync events received

**Solutions**:
1. Verify event callbacks are registered
2. Check if using correct sync function (not test_sync)
3. Ensure data directory is writable

### 6. Testing Procedure

1. **Clean Build**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   xcodebuild clean
   ```

2. **Run Diagnostics**:
   ```swift
   // In AppDelegate or initial ViewController
   Task {
       await ConnectionDebugger.runFullDiagnostics(for: dashSDK)
   }
   ```

3. **Monitor Logs**:
   - Filter console for "FFI", "Connection", "Sync"
   - Look for error patterns
   - Check peer connection counts

4. **Test Different Networks**:
   - Try mainnet vs testnet
   - Test on WiFi vs cellular
   - Test with/without VPN

### 7. Log Analysis Checklist

- [ ] FFI library version logged
- [ ] FFI initialization result logged
- [ ] Network connectivity status logged
- [ ] DNS resolution results logged
- [ ] Peer connection attempts logged
- [ ] Connection errors with details logged
- [ ] Sync progress updates logged
- [ ] Event callbacks firing logged

### 8. Recovery Actions

If connection continues to fail:

1. **Reset State**:
   ```swift
   // Clear all data and retry
   try dashSDK.clearAllData()
   FFIInitializer.reset()
   ```

2. **Force Specific Peers**:
   ```swift
   // Use known good peers
   let config = SPVClientConfiguration.testnet()
   config.additionalPeers = ["35.165.67.85:19999"]
   ```

3. **Enable Verbose Logging**:
   ```swift
   // Set to trace level
   let config = SPVClientConfiguration(logLevel: "trace")
   ```

## Next Steps

1. Implement the debug logging enhancements
2. Run full diagnostics on failing device
3. Collect and analyze logs
4. Apply targeted fixes based on findings
5. Test recovery procedures

## Expected Outcomes

After implementing this debugging plan:
- Root cause of connection failure will be identified
- Detailed logs will show exact failure point
- Recovery procedures will restore connectivity
- Future issues will be easier to diagnose