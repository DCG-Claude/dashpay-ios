# Unified FFI Integration

As of July 13, 2025, DashPay iOS has been updated to use the unified FFI library (DashUnified.xcframework) 
which combines Core SDK and Platform SDK into a single framework.

## Benefits
- 79.4% reduction in binary size (from 143MB to 29.5MB)
- Zero duplicate symbols
- Simplified build process
- Better runtime performance

## Architecture
The unified library uses a function pointer architecture where Platform SDK 
can call Core SDK functions via registered callbacks.

## Changes Made

### Libraries
- **Removed**:
  - `DashPayiOS/Libraries/DashSDK.xcframework`
  - `DashPayiOS/Libraries/libdash_spv_ffi*.a`
- **Added**:
  - `DashPayiOS/Libraries/DashUnified.xcframework`
  - `DashPayiOS/Libraries/dash_unified_ffi.h`
- **Kept**:
  - `DashPayiOS/Libraries/libkey_wallet_ffi*.a` (remains separate)

### Code Updates
- **Bridging Header**: Updated to import `dash_unified_ffi.h`
- **UnifiedFFIInitializer**: Created to manage unified library initialization
- **PlatformSDKWrapper**: Updated to use unified initialization
- **Type Changes**: Updated from `DashSDKNetwork` to `FFINetwork`

## Initialization
1. `dash_unified_init()` - Initialize the unified library (called in app init)
2. Create Core SDK client
3. `dash_unified_register_core_sdk_handle()` - Register for callbacks (optional)
4. Create Platform SDK instance

## Known Issues
1. Type visibility between C and Swift requires careful header management
2. Some types like `FFINetwork` need to be properly exposed through bridging headers
3. Module imports need to be removed in favor of bridging header imports

## Next Steps
1. Complete type mapping between C FFI types and Swift
2. Test all functionality with unified library
3. Update CI/CD pipelines to use unified framework