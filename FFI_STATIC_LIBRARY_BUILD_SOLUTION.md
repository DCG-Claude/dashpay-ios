# FFI Static Library Build Solution for iOS

## Problem Summary

When building Rust FFI libraries for iOS, you're encountering:
1. Cargo attempting to build dynamic libraries (`.dylib`) even when specifying `--crate-type=staticlib`
2. Linking errors: "building for 'iOS-simulator', but linking in object file built for 'iOS'"
3. The `crate-type` array in `Cargo.toml` including `cdylib` which iOS doesn't support

## Root Causes

1. **iOS doesn't support dynamic libraries**: iOS requires static linking, so `cdylib` crate type is incompatible
2. **Wrong target triple**: Using `aarch64-apple-ios` instead of `aarch64-apple-ios-sim` for simulator builds
3. **Cargo behavior**: When multiple crate types are specified, Cargo may still attempt to build all types

## Solutions

### 1. Force Static-Only Builds

#### Option A: Modify Cargo.toml (Recommended)
Remove `cdylib` from the crate-type array in your FFI crates' `Cargo.toml`:

```toml
[lib]
crate-type = ["staticlib", "rlib"]  # Remove "cdylib"
```

#### Option B: Use cargo rustc with proper flags (Rust 1.64+)
```bash
# For Rust 1.64 and newer - note the placement of --crate-type
cargo rustc --release --target aarch64-apple-ios-sim --crate-type=staticlib -p dash-spv-ffi
```

#### Option C: Use cargo-crate-type tool
```bash
# Install the tool
cargo install cargo-crate-type

# Build with forced static type
cargo crate-type static
cargo build --release --target aarch64-apple-ios-sim -p dash-spv-ffi
```

### 2. Fix iOS Simulator Target Issue

The critical fix is using the correct target triple for iOS simulator:

```bash
# WRONG - This is for iOS device
cargo build --target aarch64-apple-ios

# CORRECT - This is for iOS simulator on Apple Silicon
cargo build --target aarch64-apple-ios-sim

# CORRECT - This is for iOS simulator on Intel
cargo build --target x86_64-apple-ios-sim
```

### 3. Updated Build Script

Here's an updated version of your build commands that should work:

```bash
#!/bin/bash
set -e

# Ensure we have the correct targets
rustup target add aarch64-apple-ios-sim
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios-sim

# Clean any previous builds to avoid linking issues
cargo clean

# Build for iOS Simulator (Apple Silicon) - STATIC ONLY
echo "Building for iOS Simulator (arm64)..."
cargo rustc --release --target aarch64-apple-ios-sim --crate-type=staticlib -p dash-spv-ffi
cargo rustc --release --target aarch64-apple-ios-sim --crate-type=staticlib -p key-wallet-ffi

# Build for iOS Device (arm64) - STATIC ONLY
echo "Building for iOS Device (arm64)..."
cargo rustc --release --target aarch64-apple-ios --crate-type=staticlib -p dash-spv-ffi
cargo rustc --release --target aarch64-apple-ios --crate-type=staticlib -p key-wallet-ffi

# Build for iOS Simulator (x86_64) - STATIC ONLY
echo "Building for iOS Simulator (x86_64)..."
cargo rustc --release --target x86_64-apple-ios-sim --crate-type=staticlib -p dash-spv-ffi || true
cargo rustc --release --target x86_64-apple-ios-sim --crate-type=staticlib -p key-wallet-ffi || true
```

### 4. Environment Variables to Force Static Builds

You can also use environment variables to influence the build:

```bash
# Force static linking
export RUSTFLAGS="-C target-feature=+crt-static"

# Disable dynamic linking features
export CARGO_CFG_TARGET_FEATURE="crt-static"
```

### 5. Platform-Specific Cargo.toml Configuration

For a more permanent solution, you can use platform-specific configurations in `Cargo.toml`:

```toml
[target.'cfg(target_os = "ios")'.lib]
crate-type = ["staticlib"]

[target.'cfg(not(target_os = "ios"))'.lib]
crate-type = ["cdylib", "staticlib", "rlib"]
```

### 6. Verification

After building, verify the output:

```bash
# Check that only .a files are produced (no .dylib)
ls -la target/aarch64-apple-ios-sim/release/*.a
ls -la target/aarch64-apple-ios/release/*.a

# Verify the architecture of the built libraries
lipo -info target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a
# Should show: "Non-fat file: ... is architecture: arm64"

# Check for any unwanted dylib files
find target -name "*.dylib" -type f
# Should return nothing for iOS targets
```

## Complete Working Solution

The most reliable approach is:

1. **Use correct target triples**: `aarch64-apple-ios-sim` for simulator, not `aarch64-apple-ios`
2. **Force static-only builds**: Use `cargo rustc --crate-type=staticlib` with Rust 1.64+
3. **Clean between builds**: Run `cargo clean` if switching targets
4. **Verify outputs**: Check that only `.a` files are produced

## Additional Notes

- When using `cargo rustc`, the output may be in `target/<triple>/release/deps/` instead of `target/<triple>/release/`
- iOS simulator on Apple Silicon (M1/M2) requires `aarch64-apple-ios-sim`, not the old `x86_64-apple-ios`
- The `x86_64-apple-ios-sim` target should be used for Intel Mac simulators
- Always ensure your Rust toolchain is up to date: `rustup update`