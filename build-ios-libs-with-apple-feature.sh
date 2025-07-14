#!/bin/bash

# Build script that ensures bls-dash-sys uses the apple feature
set -e

echo "Building Rust FFI libraries for iOS with apple feature..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if rust-dashcore directory exists
RUST_DASHCORE_DIR="../rust-dashcore"
if [ ! -d "$RUST_DASHCORE_DIR" ]; then
    echo -e "${RED}Error: rust-dashcore directory not found at $RUST_DASHCORE_DIR${NC}"
    exit 1
fi

# Navigate to rust-dashcore
cd "$RUST_DASHCORE_DIR"

# Create a .cargo/config.toml to add the apple feature
echo -e "${YELLOW}Creating .cargo/config.toml to enable apple feature...${NC}"
mkdir -p .cargo
cat > .cargo/config.toml << 'EOF'
[target.'cfg(any(target_os = "ios", target_os = "macos"))']
rustflags = ["--cfg", "feature=\"apple\""]

[env]
CARGO_FEATURE_APPLE = "1"
EOF

# Install iOS targets
rustup target add aarch64-apple-ios-sim
rustup target add aarch64-apple-ios

# Clean build to force rebuild with apple feature
echo -e "${YELLOW}Cleaning build artifacts...${NC}"
cargo clean

# Set environment for iOS builds
export IPHONEOS_DEPLOYMENT_TARGET="14.0"
export CARGO_FEATURE_APPLE="1"

# Build for iOS Simulator (arm64)
echo -e "${GREEN}Building for iOS Simulator (arm64) with apple feature...${NC}"
cargo build --release --target aarch64-apple-ios-sim -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios-sim -p key-wallet-ffi

# Build for iOS Device (arm64)
echo -e "${GREEN}Building for iOS Device (arm64) with apple feature...${NC}"
cargo build --release --target aarch64-apple-ios -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios -p key-wallet-ffi

# Remove temporary config
rm -f .cargo/config.toml

# Navigate back to dashpay-ios
cd ../dashpay-ios

# Create Libraries directory
mkdir -p DashPayiOS/Libraries

# Copy the libraries
echo -e "${GREEN}Copying libraries...${NC}"
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a" DashPayiOS/Libraries/libdash_spv_ffi_sim.a
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios/release/libdash_spv_ffi.a" DashPayiOS/Libraries/libdash_spv_ffi_ios.a
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios-sim/release/libkey_wallet_ffi.a" DashPayiOS/Libraries/libkey_wallet_ffi_sim.a
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios/release/libkey_wallet_ffi.a" DashPayiOS/Libraries/libkey_wallet_ffi_ios.a

# Copy headers
mkdir -p DashPayiOS/Libraries/include
cp "$RUST_DASHCORE_DIR/dash-spv-ffi/include/dash_spv_ffi.h" DashPayiOS/Libraries/include/ 2>/dev/null || true
cp "$RUST_DASHCORE_DIR/key-wallet-ffi/include/key_wallet_ffi.h" DashPayiOS/Libraries/include/ 2>/dev/null || true

# Create symlinks
cd DashPayiOS/Libraries
ln -sf libdash_spv_ffi_sim.a libdash_spv_ffi.a
ln -sf libkey_wallet_ffi_sim.a libkey_wallet_ffi.a
cd ../..

# Show results
ls -lah DashPayiOS/Libraries/*.a

echo ""
echo -e "${GREEN}✅ Build complete with apple feature enabled!${NC}"