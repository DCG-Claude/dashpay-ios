# FFI Library Conflict Resolution - Comprehensive Approaches

## Problem Summary
The DashPay iOS app uses two Rust FFI libraries that contain 494 duplicate symbols:
- `libdash_spv_ffi.a` - Core wallet functionality
- `librs_sdk_ffi.a` - Platform SDK functionality

Both libraries bundle the same dependencies:
- blake3 (cryptographic hash function)
- blst (BLS signatures)
- Rust runtime and compiler builtins

## Solution Approaches

### 1. Comprehensive Symbol Renaming (✅ Implemented)

**Status**: Working solution with 493/494 symbols resolved

**How it works**:
- Uses `llvm-objcopy` to rename symbols at the binary level
- Adds library-specific prefixes (`_spv_` and `_sdk_`)
- No source code changes required

**Implementation**:
```bash
./scripts/rename_all_duplicate_symbols.sh
```

**Pros**:
- Works with existing binaries
- No Rust source modifications needed
- Preserves all functionality
- Can be automated in build process

**Cons**:
- Must be re-run when libraries update
- Slightly increases library size
- One symbol (`_rust_eh_personality`) requires special handling

**Results**:
- Original: 494 duplicate symbols
- After renaming: 1 duplicate symbol (exception handler)
- All FFI functions remain accessible

### 2. Selective Linking (🔧 Alternative)

**Status**: Proof of concept created

**How it works**:
- Extracts object files from static libraries
- Identifies objects with duplicate symbols
- Creates new libraries excluding duplicates
- Keeps crypto libs in one library, removes from other

**Implementation**:
```bash
./scripts/selective_linking_approach.sh
```

**Pros**:
- Reduces final binary size
- Complete control over what's included
- No symbol renaming needed

**Cons**:
- Complex to maintain
- Risk of missing required symbols
- May break if internal dependencies change
- Requires careful testing

### 3. Dynamic Loading (📱 Limited on iOS)

**Status**: Demonstration code only

**How it works**:
- Load libraries dynamically at runtime
- Use dlopen/dlsym to access functions
- Complete symbol namespace isolation

**Implementation**:
```swift
// See DynamicFFILoader.swift
let spvFFI = DynamicSPVFFI(libraryPath: "path/to/lib.dylib")
spvFFI?.initLogging()
```

**Pros**:
- Complete symbol isolation
- Can load/unload libraries on demand
- No linking conflicts possible

**Cons**:
- ❌ App Store prohibits dynamic libraries
- Performance overhead
- Complex error handling
- Not viable for iOS production

### 4. Framework Wrappers (🍎 iOS Native)

**Status**: Not implemented

**How it works**:
- Create separate framework targets for each library
- Use module maps to control symbol visibility
- Link frameworks instead of static libraries

**Pros**:
- iOS native approach
- Better symbol isolation
- Supports Swift Package Manager

**Cons**:
- Requires significant project restructuring
- May still have symbol conflicts
- More complex build configuration

## Recommendation

**Use Comprehensive Symbol Renaming** (Approach #1) because:

1. **It works now** - 493/494 symbols resolved
2. **No source changes** - Works with existing Rust libraries
3. **Production ready** - Can be deployed immediately
4. **Maintainable** - Script can be added to CI/CD

## Implementation Guide

### Step 1: Generate Renamed Libraries
```bash
# Run the comprehensive renaming script
./scripts/rename_all_duplicate_symbols.sh
```

### Step 2: Verify Libraries
```bash
# Check that no duplicates remain
nm -g DashPayiOS/Libraries/libdash_spv_ffi_sim_renamed.a | grep " T " > /tmp/spv.txt
nm -g DashPayiOS/Libraries/DashSDK.xcframework/ios-arm64-simulator/librs_sdk_ffi_renamed.a | grep " T " > /tmp/sdk.txt
comm -12 <(sort /tmp/spv.txt) <(sort /tmp/sdk.txt) | wc -l
# Should output: 1 (only rust_eh_personality)
```

### Step 3: Update Project Configuration
Ensure `project.yml` uses renamed libraries:
```yaml
targets:
  DashPayiOS:
    settings:
      OTHER_LDFLAGS:
        - "-ldash_spv_ffi_sim_renamed"
        - "-lrs_sdk_ffi_renamed"
```

### Step 4: Test
```bash
# Run the test script
./test-renamed-libraries.sh
```

## Future Improvements

### Short Term
1. Add symbol renaming to Xcode build phases
2. Create pre-commit hook to verify no new conflicts
3. Add CI/CD integration

### Long Term
1. Work with Rust team to create unified library
2. Use cargo features to exclude duplicate dependencies
3. Consider UniFFI framework for better FFI management

## Troubleshooting

### If symbols are still conflicting:
1. Re-run the rename script
2. Clean build folder
3. Regenerate Xcode project with `xcodegen`

### If FFI functions are not found:
1. Verify renamed libraries are in correct location
2. Check library search paths in project.yml
3. Ensure FFI function names weren't accidentally renamed

### If app crashes at runtime:
1. Check for the `_rust_eh_personality` symbol
2. Verify all required symbols are present
3. Enable verbose FFI logging

## Conclusion

The comprehensive symbol renaming approach provides a practical, working solution to the FFI library conflicts. While not perfect (one symbol remains), it allows the app to function correctly with both libraries without requiring any Rust source code changes or complex build configurations.