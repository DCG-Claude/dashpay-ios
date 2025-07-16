# Building and Updating FFI Libraries for DashPay iOS

## Overview

DashPay iOS depends on Rust FFI (Foreign Function Interface) libraries from the rust-dashcore project. These libraries provide the core SPV (Simplified Payment Verification) functionality and HD wallet operations.

## Prerequisites

1. **rust-dashcore** must be cloned at the same level as dashpay-ios:
   ```
   parent-directory/
   ├── dashpay-ios/
   └── rust-dashcore/
   ```

2. **Rust toolchain** must be installed:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

3. **Xcode** and command line tools must be installed

## Building Libraries

### Automatic Build (Recommended)

Run the build script from the dashpay-ios directory:

```bash
cd /path/to/dashpay-ios
./build-ios-libs.sh
```

This script will:
1. Install required iOS Rust targets
2. Build FFI libraries for both simulator and device
3. Create universal binaries for simulator (arm64 + x86_64)
4. Copy libraries to `DashPayiOS/Libraries/`
5. Create appropriate symlinks

### Manual Build

If you need to build manually:

```bash
# Navigate to rust-dashcore
cd ../rust-dashcore

# Add iOS targets
rustup target add aarch64-apple-ios-sim aarch64-apple-ios x86_64-apple-ios

# Build for simulator (Apple Silicon)
cargo build --release --target aarch64-apple-ios-sim -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios-sim -p key-wallet-ffi

# Build for device
cargo build --release --target aarch64-apple-ios -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios -p key-wallet-ffi

# Copy to dashpay-ios
cp target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a ../dashpay-ios/DashPayiOS/Libraries/libdash_spv_ffi_sim.a
cp target/aarch64-apple-ios/release/libdash_spv_ffi.a ../dashpay-ios/DashPayiOS/Libraries/libdash_spv_ffi_ios.a
# ... repeat for key_wallet_ffi
```

## Library Architecture

The project uses separate libraries for simulator and device:

- `libdash_spv_ffi_sim.a` - iOS Simulator (arm64 + x86_64 universal)
- `libdash_spv_ffi_ios.a` - iOS Device (arm64 only)
- `libkey_wallet_ffi_sim.a` - iOS Simulator (arm64 + x86_64 universal)
- `libkey_wallet_ffi_ios.a` - iOS Device (arm64 only)

Symlinks are used to select the active library:
- `libdash_spv_ffi.a` → points to either sim or ios version
- `libkey_wallet_ffi.a` → points to either sim or ios version

## Library Selection for Xcode Builds

The build script creates symlinks that default to simulator libraries. Before building for a different target, manually update the symlinks:

### For Simulator Builds (default)
```bash
cd DashPayiOS/Libraries
ln -sf libdash_spv_ffi_sim.a libdash_spv_ffi.a
ln -sf libkey_wallet_ffi_sim.a libkey_wallet_ffi.a
```

### For Device Builds
```bash
cd DashPayiOS/Libraries
ln -sf libdash_spv_ffi_ios.a libdash_spv_ffi.a
ln -sf libkey_wallet_ffi_ios.a libkey_wallet_ffi.a
```

### Using the Helper Script
You can also use the provided script:
```bash
# From dashpay-ios directory
./select-library.sh sim    # for simulator
./select-library.sh ios    # for device
```

**Note**: Always clean build folder (⇧⌘K) in Xcode after switching library targets.

## Troubleshooting

### Library Not Found Errors

1. Ensure libraries exist in `DashPayiOS/Libraries/`
2. Check symlinks are pointing to the correct files:
   ```bash
   ls -la DashPayiOS/Libraries/*.a
   ```

### Architecture Mismatch

If you see "building for iOS Simulator, but linking in object file built for iOS":
- You're using the wrong library variant
- Run `select-library.sh sim` for simulator builds
- Run `select-library.sh ios` for device builds

### Build Failures

1. Clean build folder: Product → Clean Build Folder (⇧⌘K)
2. Delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*DashPay*
   ```
3. Rebuild libraries with `./build-ios-libs.sh`

## Updating Libraries

When rust-dashcore is updated:

1. Pull latest changes in rust-dashcore:
   ```bash
   cd ../rust-dashcore
   git pull
   ```

2. Rebuild libraries:
   ```bash
   cd ../dashpay-ios
   ./build-ios-libs.sh
   ```

3. Clean and rebuild in Xcode

## Version Management

To check library versions:
```bash
# Check file dates
ls -la DashPayiOS/Libraries/lib*.a

# Check file sizes (newer versions are typically larger)
du -h DashPayiOS/Libraries/lib*.a

# Check symbols (requires developer tools)
nm DashPayiOS/Libraries/libdash_spv_ffi.a | grep peer_count
```

## CI/CD Integration

For automated builds, ensure your CI pipeline:
1. Has rust-dashcore checked out at the same directory level
2. Has Rust toolchain installed
3. Runs `./build-ios-libs.sh` before Xcode build
4. Runs `./select-library.sh sim` or `./select-library.sh ios` based on build target
5. Cleans build folder between different target builds