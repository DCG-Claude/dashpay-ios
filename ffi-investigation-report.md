# FFI Initialization Failure Investigation Report

## Summary
The FFI initialization fails in the iOS simulator due to improper library linking in the Xcode project configuration.

## Root Cause Analysis

### 1. Library Architecture
- The FFI libraries are correctly built for arm64 architecture:
  - `libdash_spv_ffi_sim.a`: arm64 (iOS Simulator)
  - `libdash_spv_ffi_ios.a`: arm64 (iOS Device)

### 2. Project Configuration Issue
**PRIMARY ISSUE**: The `libdash_spv_ffi_sim.a` library is being added to the project as a **Resource** instead of being properly linked:

```
30C682904D76A05B52779343 /* libdash_spv_ffi_sim.a in Resources */ = {isa = PBXBuildFile; ...}
```

This means the library is copied to the app bundle but NOT linked during compilation, causing FFI symbols to be undefined at runtime.

### 3. FFI Initialization Flow
1. `AppState.initializeSDK()` is called
2. `DashSDK` constructor attempts to create `SPVClient`
3. `SPVClient` tries to initialize FFI using `FFIInitializer`
4. `dash_spv_ffi_init_logging()` is called but the symbol is not found
5. Initialization fails

### 4. Evidence
- The FFI symbols exist in the library:
  - `_dash_spv_ffi_init_logging` at offset 0x10d6c
  - `_dash_spv_ffi_config_new` at offset 0x11ab8
- The module map is correctly configured
- The header files are properly imported

## Solution

### Fix 1: Update Xcode Project Configuration
The `libdash_spv_ffi_sim.a` library needs to be:
1. Removed from "Copy Bundle Resources" build phase
2. Added to "Link Binary With Libraries" build phase

### Fix 2: Ensure Proper Library Selection
The project should conditionally link:
- `libdash_spv_ffi_sim.a` for iOS Simulator builds
- `libdash_spv_ffi_ios.a` for iOS Device builds

### Fix 3: Build Settings
Ensure the following build settings:
- Library Search Paths includes: `$(PROJECT_DIR)/DashPayiOS/Libraries`
- Other Linker Flags includes: `-ldash_spv_ffi_sim` (for simulator)
- Dead Code Stripping: NO (temporarily for debugging)

## Temporary Workarounds

### 1. Force Link Symbols
Add to a Swift file in the main target:
```swift
@_silgen_name("dash_spv_ffi_init_logging")
func forceLink_dash_spv_ffi_init_logging(_: UnsafePointer<CChar>) -> Int32

// Force the linker to include the symbol
_ = forceLink_dash_spv_ffi_init_logging
```

### 2. Dynamic Loading
Use `dlopen()` to manually load the library at runtime (not recommended for production).

## Verification Steps

1. Check if symbols are linked:
```bash
nm -g DerivedData/.../DashPay.app/DashPay | grep dash_spv_ffi
```

2. Verify library is in Frameworks, not Resources:
```bash
find DerivedData/.../DashPay.app -name "*.a" -type f
```

3. Check dyld errors in Console.app filtering for process "DashPay"

## Additional Notes

- The renamed libraries (`libdash_spv_ffi_sim_renamed.a`) suggest there may have been symbol conflict issues
- Both SPV and SDK FFI libraries are present, which could cause conflicts
- The current architecture (arm64) is correct for Apple Silicon simulators