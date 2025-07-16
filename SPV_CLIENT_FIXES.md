# SPV Client Fixes for dashpay-ios

## Issues Fixed

### 1. Path/Network Mismatch
**Problem**: The SPV data directory was using the raw value of the network enum (e.g., "mainnet") which didn't match the actual network being used (testnet).

**Solution**: Modified `SPVClientConfiguration.setupDefaultDataDirectory()` to use `network.name.lowercased()` instead of `network.rawValue` for the directory path.

**File Changed**: `/Users/quantum/src/dashpay-ios/SwiftDashCoreSDK_backup/Core/SPVClientConfiguration.swift`

```swift
// Before:
self.dataDirectory = documentsPath.appendingPathComponent("DashSPV").appendingPathComponent(network.rawValue)

// After:
let networkDir = network.name.lowercased()
self.dataDirectory = documentsPath.appendingPathComponent("DashSPV").appendingPathComponent(networkDir)
```

### 2. Double SPV Client Initialization
**Problem**: 
- First SPV client created in `UnifiedAppState.initialize()`
- Second SPV client created in `WalletService.connect()` during auto-sync
- Both instances fight for the same directory causing "No peers connected" errors

**Solution**: 
1. Added `setSDK()` method to WalletService to accept external SDK instance
2. Modified `WalletService.connect()` to check for existing SDK before creating new one
3. Updated `UnifiedAppState` to pass its SDK instance to WalletService

**Files Changed**:
- `/Users/quantum/src/dashpay-ios/DashPayiOS/Core/Services/WalletService.swift`
- `/Users/quantum/src/dashpay-ios/DashPayiOS/App/DashPayApp.swift`

## Key Changes

### WalletService.swift

1. Added method to set SDK from external source:
```swift
func setSDK(_ dashSDK: DashSDK?) {
    logger.info("🔧 WalletService.setSDK() called")
    if let sdk = dashSDK {
        self.sdk = sdk
        logger.info("✅ WalletService SDK set from external source")
    } else {
        self.sdk = nil
        logger.info("⚠️ WalletService SDK cleared")
    }
}
```

2. Modified `connect()` to check for existing SDK:
```swift
// Check if we should reuse an existing SDK instance
if let existingSDK = sdk {
    logger.info("🔄 Reusing existing DashSDK instance")
    // Verify the network matches
    if let sdkNetwork = existingSDK.configuration?.network, sdkNetwork == wallet.network {
        logger.info("✅ Existing SDK network matches wallet network")
    } else {
        logger.info("⚠️ Existing SDK network mismatch - creating new SDK")
        sdk = nil
    }
}

// Only create new SDK if we don't have one or network changed
if sdk == nil {
    // ... create new SDK
}
```

### DashPayApp.swift

Added SDK passing to WalletService:
```swift
// Pass the SDK to WalletService to prevent double initialization
print("🔧 Setting Core SDK in WalletService...")
await MainActor.run {
    walletService.setSDK(coreSDK)
}
print("✅ WalletService SDK configured")
```

## Expected Behavior After Fixes

1. **Single SDK Instance**: Only one SPV client instance will be created and shared between UnifiedAppState and WalletService
2. **Correct Data Directory**: SPV data will be stored in the correct directory matching the network (e.g., `DashSPV/testnet` for testnet)
3. **Network Switching**: When switching networks, a new SDK instance will be created with the correct configuration
4. **Auto-sync**: Auto-sync will reuse the existing SDK instance when the network matches, preventing connection conflicts

## Testing

To verify the fixes work correctly:

1. Launch the app and create/import a wallet
2. Check logs for "Reusing existing DashSDK instance" during auto-sync
3. Verify only one SPV data directory is created matching the current network
4. Test network switching to ensure proper SDK recreation

## Additional Notes

- The FFI initialization is handled automatically by SPVClient creation
- Network mismatch detection ensures we don't accidentally use mainnet data for testnet
- The fixes maintain backward compatibility with existing wallet data