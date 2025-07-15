# FFI Library Integration Guide for DashPay iOS

## Overview

This guide documents the approach to resolving FFI library conflicts in the DashPay iOS application, which uses two Rust-based FFI libraries:

1. **libdash_spv_ffi** - Core SPV (Simplified Payment Verification) functionality
2. **librs_sdk_ffi** - Platform SDK functionality

## The Problem

When linking multiple Rust static libraries in an iOS project, duplicate symbol conflicts arise because each library includes its own copy of:
- Rust runtime components (`_rust_eh_personality`)
- Compiler builtins (`___absvdi2`, `___addvdi3`, etc.)
- Platform-specific atomics (`__aarch64_cas*` functions)

This causes the app to hang during initialization when calling `dash_spv_ffi_init_logging`.

## Solutions Implemented

### 1. Immediate Solution: FFI Initializer with Timeout Protection

We've implemented a robust FFI initialization system that:
- Provides timeout protection to prevent hangs
- Implements retry logic for resilience
- Allows graceful degradation if initialization fails
- Supports mock mode for development

**Key Files:**
- `/DashPayiOS/SwiftDashCoreSDK/FFI/FFIInitializer.swift` - FFI initialization manager
- `/DashPayiOS/SwiftDashCoreSDK/Core/SPVClient.swift` - Updated to use FFI initializer

**Usage:**
```swift
// Initialize FFI libraries with error handling
try FFIInitializer.initialize(logLevel: "info")

// Or use with retry logic
try FFIInitializer.initializeWithRetry(maxAttempts: 3)

// Or use lazy initialization
try FFIInitializer.ensureInitialized()
```

### 2. Symbol Renaming Solution

We've created a script that renames conflicting symbols in the FFI libraries to avoid conflicts.

**Script:** `/scripts/rename_ffi_symbols.sh`

**How it works:**
1. Extracts symbols from both libraries
2. Identifies common symbols (491 conflicts found)
3. Renames symbols with library-specific prefixes:
   - SPV library: `_spv_` prefix
   - SDK library: `_sdk_` prefix
4. Creates new libraries with renamed symbols

**Usage:**
```bash
./scripts/rename_ffi_symbols.sh
```

This creates:
- `libdash_spv_ffi_sim_renamed.a`
- `librs_sdk_ffi_renamed.a`

### 3. Build Configuration Options

To use the renamed libraries, update `project.yml`:

```yaml
targets:
  DashPayiOS:
    settings:
      base:
        OTHER_LDFLAGS:
          - "-L$(PROJECT_DIR)/DashPayiOS/Libraries"
          - "-ldash_spv_ffi_sim_renamed"  # Use renamed library
          - "-lrs_sdk_ffi_renamed"         # Use renamed library
```

## Alternative Approaches

### 1. Unified FFI Library (Recommended for Production)

Create a single Rust crate that combines both libraries:

```rust
// dash-unified-ffi/src/lib.rs
pub use dash_spv::*;
pub use dash_sdk::*;

// Re-export all FFI functions
pub use dash_spv_ffi::*;
pub use dash_sdk_ffi::*;
```

Benefits:
- Single library = no conflicts
- Easier to maintain
- Better optimization opportunities

### 2. Dynamic Libraries

Convert to `.dylib` format:
- No symbol conflicts between dynamic libraries
- Requires code signing
- Slightly larger app size

### 3. Selective Symbol Export

Use Rust's `#[no_mangle]` more selectively and hide internal symbols:

```rust
// Only export necessary FFI functions
#[no_mangle]
pub extern "C" fn dash_spv_public_function() { }

// Hide internal functions
#[doc(hidden)]
fn internal_function() { }
```

## Testing Strategy

1. **Unit Tests**: Test each FFI function independently
2. **Integration Tests**: Test cross-library functionality
3. **Timeout Tests**: Verify initialization doesn't hang
4. **Symbol Tests**: Verify no duplicate symbols:
   ```bash
   nm -g lib1.a lib2.a | sort | uniq -d
   ```

## Deployment Checklist

- [ ] Run symbol renaming script for all architectures
- [ ] Update project.yml with renamed libraries
- [ ] Test on simulator (x86_64, arm64)
- [ ] Test on device (arm64)
- [ ] Verify no runtime crashes
- [ ] Check memory usage and performance
- [ ] Update CI/CD scripts

## Troubleshooting

### Issue: Initialization still hangs
- Check if both libraries are being linked
- Verify symbol renaming was successful
- Try increasing timeout in FFIInitializer

### Issue: Undefined symbols
- Ensure all required symbols are exported
- Check library link order in project.yml
- Verify architecture matches (simulator vs device)

### Issue: Runtime crashes
- Check for ABI incompatibilities
- Verify Rust compiler versions match
- Enable verbose logging for debugging

## Future Improvements

1. **Automated Build Process**: Integrate symbol renaming into Xcode build phases
2. **CI/CD Integration**: Automate library processing in build pipeline
3. **Version Management**: Track FFI library versions and compatibility
4. **Performance Monitoring**: Add metrics for FFI call performance

## References

- [Rust FFI Omnibus](https://jakegoulding.com/rust-ffi-omnibus/)
- [Apple XCFramework Documentation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- [Rust Issue #79408](https://github.com/rust-lang/rust/issues/79408) - XCFramework compatibility
- [UniFFI Documentation](https://mozilla.github.io/uniffi-rs/) - Mozilla's FFI framework