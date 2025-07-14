# DashPay iOS Crash Fixes Summary

## Issues Fixed

### 1. Balance Entity Validation Errors
**Problem**: Balance SwiftData model fields were nil but marked as required, causing validation errors when trying to save.

**Fixes Applied**:
- Modified `HDWatchedAddress` initializer to create a default Balance object instead of nil
- Added safe handling for optional `mempoolInstant` property from SDK Balance
- Ensured Balance entities are properly inserted into ModelContext before assigning to relationships

### 2. ModelContext Threading Issues  
**Problem**: SwiftData ModelContext was being used off the main thread, causing "Unbinding from the main queue" errors and fatal crashes.

**Fixes Applied**:
- Added `@MainActor` attribute to `watchAccountAddresses` method
- Wrapped all SwiftData operations in `MainActor.run` blocks
- Added thread assertions to verify SwiftData operations occur on main thread
- Ensured all context.save() calls happen on MainActor

### 3. SDK Double Initialization
**Problem**: The SDK appeared to be initializing twice based on duplicate log messages.

**Fixes Applied**:
- Added thread-safe locks for both FFI and SDK initialization
- Implemented double-check locking pattern to prevent concurrent SDK creation
- Added proper synchronization using NSLock for initialization critical sections

## Key Changes by File

### `/Core/Models/HDWalletModels.swift`
- Updated `updateBalanceSafely` methods to ensure main thread execution
- Added proper ModelContext insertion before relationship assignment
- Added thread assertions for debugging

### `/Core/Models/Balance.swift`
- Added safe handling for optional `mempoolInstant` property
- Ensured all SDK Balance properties are safely unwrapped with defaults

### `/Core/Services/WalletService.swift`
- Added thread-safe locks for FFI and SDK initialization
- Wrapped balance update operations in MainActor.run blocks
- Added @MainActor to watchAccountAddresses method
- Ensured all SwiftData operations happen on main thread

### `/Core/Models/HDWalletModels.swift` 
- Modified HDWatchedAddress initializer to create default Balance instead of nil
- This prevents validation errors when addresses are first created

## Testing Recommendations

1. **Balance Updates**: Verify that balance updates work correctly when:
   - Connecting to network for first time
   - Receiving transactions
   - Syncing existing wallet

2. **Threading**: Monitor for any SwiftData threading warnings in console

3. **SDK Initialization**: Verify SDK only initializes once by checking logs for duplicate initialization messages

4. **Crash Prevention**: Test the following scenarios that previously caused crashes:
   - Fresh wallet creation and initial sync
   - Wallet restoration from seed
   - Background/foreground transitions during sync
   - Multiple rapid connection attempts

## Additional Notes

- All SwiftData operations now happen on MainActor to prevent threading issues
- Balance entities are always initialized with default values to prevent nil validation errors  
- SDK initialization is now thread-safe and prevents double initialization
- The fixes maintain backward compatibility with existing wallet data