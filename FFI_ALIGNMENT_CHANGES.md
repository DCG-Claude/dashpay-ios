# FFI Library Alignment Changes

This document summarizes the changes made to align dashpay-ios with rust-dashcore's FFI library approach.

## Problem
The dashpay-ios project was using renamed libraries (with _renamed suffix) to avoid symbol conflicts, but this approach was causing FFI bridge initialization failures. The project needed to be aligned with how rust-dashcore handles FFI libraries through Swift Package Manager.

## Changes Made

### 1. Removed Renamed Libraries
- Deleted all `*_renamed.a` files from `/DashPayiOS/Libraries/`
- These renamed libraries were causing symbol resolution issues

### 2. Updated select-library.sh Script
- Changed from creating symlinks to verification-only mode
- The script now just confirms that libraries come from the Swift Package
- Location: `/select-library.sh`

### 3. Modified Xcode Project Configuration
- **Removed from Resources Build Phase:**
  - All `.a` library files (they should never be in Resources)
  - `libdash_spv_ffi.a`, `libdash_spv_ffi_ios.a`, `libdash_spv_ffi_sim.a`
  - `libkey_wallet_ffi.a`, `libkey_wallet_ffi_ios.a`, `libkey_wallet_ffi_sim.a`
  - `libkey_wallet_ffi_sim_filtered.a`

- **Removed from LIBRARY_SEARCH_PATHS:**
  - `$(PROJECT_DIR)/DashPayiOS/Libraries`
  - `$(PROJECT_DIR)/DashPayiOS/Libraries/DashSDK.xcframework/ios-arm64-simulator`

- **Cleaned up PBXFileReference entries:**
  - Removed all references to individual library files
  - Kept only DashSDK.xcframework reference

### 4. Updated rust-dashcore Package.swift
- Removed `/Users/quantum/src/dashpay-ios/DashPayiOS/Libraries` from linker search paths
- This ensures the Swift Package doesn't accidentally pick up old libraries

### 5. Library Organization
- Moved old library files to `/DashPayiOS/Libraries/backup/`
- The Libraries directory now only contains DashSDK.xcframework
- All FFI libraries (libdash_spv_ffi, libkey_wallet_ffi) come from the Swift Package

## How It Works Now

1. **Swift Package Manager** provides the FFI libraries through:
   - `DashSPVFFI` target → provides libdash_spv_ffi
   - `KeyWalletFFI` target → provides libkey_wallet_ffi
   - These are linked as part of the SwiftDashCoreSDK package

2. **No Manual Library Management** needed:
   - No symlinks required
   - No library selection based on platform
   - SPM handles platform-specific library selection automatically

3. **DashSDK.xcframework** is embedded normally:
   - Added to "Embed Frameworks" build phase
   - Provides the high-level SDK interface

## Benefits

1. **No Symbol Conflicts**: Using original library names from rust-dashcore
2. **Simplified Build Process**: No need for build scripts to manage libraries
3. **Consistent with rust-dashcore**: Same approach as the example app
4. **Automatic Platform Handling**: SPM manages simulator vs device libraries

## Testing

Run the test script to verify the alignment:
```bash
swift test-ffi-alignment.swift
```

This will confirm:
- SDK can be imported
- Configuration can be created
- FFI symbols are available
- SDK instance can be created without symbol conflicts