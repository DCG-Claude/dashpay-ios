# Symbol De-duplication/Renaming Removal Changes

This document summarizes the changes made to remove symbol de-duplication/renaming from dashpay-ios to match how rust-dashcore works.

## Overview
The goal was to simplify the build process by using original libraries directly and letting the linker handle any duplicate symbols, rather than using renamed libraries.

## Changes Made

### 1. Xcode Project File Changes (`DashPayiOS.xcodeproj/project.pbxproj`)
- Removed all references to renamed libraries (`*_renamed.a`)
- Removed 5 PBXBuildFile entries for renamed libraries
- Removed 5 PBXFileReference entries for renamed libraries
- Removed 5 entries from the Resources build phase
- Removed 5 entries from the Libraries group

Libraries removed:
- `librs_sdk_ffi_renamed.a`
- `libkey_wallet_ffi_sim_renamed.a`
- `libdash_spv_ffi_ios_renamed.a`
- `libdash_spv_ffi_sim_renamed.a`
- `libkey_wallet_ffi_ios_renamed.a`

### 2. Renaming Scripts Disabled
The following scripts were disabled by renaming them with `.disabled` extension:
- `/Users/quantum/src/dashpay-ios/scripts/rename_ffi_symbols.sh` → `.disabled`
- `/Users/quantum/src/dashpay-ios/scripts/rename_all_duplicate_symbols.sh` → `.disabled`
- All `rename*.sh` scripts in the root directory

### 3. Build Configuration
- The `select-library.sh` script was already configured correctly to use original libraries
- No preprocessor macros or build flags related to symbol renaming were found

### 4. Code Updates
- Updated `FFIIntegrationTests.swift` - removed comment about renamed libraries
- Updated `test-sdk-init.swift` - changed library paths from renamed to original

### 5. Files Backed Up
- `DashPayiOS.xcodeproj/project.pbxproj.backup` - backup of the original project file

## Verification
The project now uses the original libraries directly:
- `libdash_spv_ffi_sim.a` (instead of `libdash_spv_ffi_sim_renamed.a`)
- `libkey_wallet_ffi_sim.a` (instead of `libkey_wallet_ffi_sim_renamed.a`)
- `libdash_spv_ffi_ios.a` (instead of `libdash_spv_ffi_ios_renamed.a`)
- `libkey_wallet_ffi_ios.a` (instead of `libkey_wallet_ffi_ios_renamed.a`)
- `librs_sdk_ffi.a` (inside xcframework, instead of `librs_sdk_ffi_renamed.a`)

## Next Steps
1. Clean build folder and rebuild the project
2. Test on both simulator and device
3. Monitor for any duplicate symbol errors during linking
4. If duplicate symbol errors occur, they can be resolved with appropriate linker flags

## Rollback Instructions
If needed, the changes can be rolled back by:
1. Restore the project file: `cp project.pbxproj.backup project.pbxproj`
2. Re-enable the scripts: remove `.disabled` extension from the script files
3. The renamed libraries are still present in the `Libraries/renamed/` directory