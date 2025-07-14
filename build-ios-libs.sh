#!/bin/bash

# Build script for updating iOS FFI libraries in DashPay iOS
# This script builds the rust-dashcore FFI libraries and copies them to the correct location
set -e

echo "Building Rust FFI libraries for DashPay iOS..."

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
    echo "Please ensure rust-dashcore is cloned at the same level as dashpay-ios"
    exit 1
fi

# Navigate to rust-dashcore
cd "$RUST_DASHCORE_DIR"

# Install iOS targets if not already installed
echo -e "${YELLOW}Installing iOS rust targets...${NC}"
rustup target add aarch64-apple-ios-sim
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios

# Build for iOS Simulator (arm64) - for Apple Silicon Macs
echo -e "${GREEN}Building for iOS Simulator (arm64)...${NC}"
cargo build --release --target aarch64-apple-ios-sim -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios-sim -p key-wallet-ffi

# Build for iOS Device (arm64)
echo -e "${GREEN}Building for iOS Device (arm64)...${NC}"
cargo build --release --target aarch64-apple-ios -p dash-spv-ffi
cargo build --release --target aarch64-apple-ios -p key-wallet-ffi

# Build for iOS Simulator (x86_64) - for Intel Macs
echo -e "${GREEN}Building for iOS Simulator (x86_64)...${NC}"
cargo build --release --target x86_64-apple-ios -p dash-spv-ffi || echo -e "${YELLOW}Warning: x86_64 build failed (OK if on Apple Silicon)${NC}"
cargo build --release --target x86_64-apple-ios -p key-wallet-ffi || echo -e "${YELLOW}Warning: x86_64 build failed (OK if on Apple Silicon)${NC}"

# Create universal binary for simulator (if both architectures built)
echo -e "${GREEN}Creating universal binary for iOS Simulator...${NC}"
mkdir -p target/ios-simulator-universal/release

# Check if both architectures exist before creating universal binary
if [ -f "target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a" ] && [ -f "target/x86_64-apple-ios/release/libdash_spv_ffi.a" ]; then
    lipo -create \
        target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a \
        target/x86_64-apple-ios/release/libdash_spv_ffi.a \
        -output target/ios-simulator-universal/release/libdash_spv_ffi.a
    echo -e "${GREEN}Created universal libdash_spv_ffi.a${NC}"
else
    echo -e "${YELLOW}Using arm64-only simulator library (no x86_64 available)${NC}"
    cp target/aarch64-apple-ios-sim/release/libdash_spv_ffi.a target/ios-simulator-universal/release/
fi

if [ -f "target/aarch64-apple-ios-sim/release/libkey_wallet_ffi.a" ] && [ -f "target/x86_64-apple-ios/release/libkey_wallet_ffi.a" ]; then
    lipo -create \
        target/aarch64-apple-ios-sim/release/libkey_wallet_ffi.a \
        target/x86_64-apple-ios/release/libkey_wallet_ffi.a \
        -output target/ios-simulator-universal/release/libkey_wallet_ffi.a
    echo -e "${GREEN}Created universal libkey_wallet_ffi.a${NC}"
else
    echo -e "${YELLOW}Using arm64-only simulator library (no x86_64 available)${NC}"
    cp target/aarch64-apple-ios-sim/release/libkey_wallet_ffi.a target/ios-simulator-universal/release/
fi

# Navigate back to dashpay-ios
cd ../dashpay-ios

# Create Libraries directory if it doesn't exist
mkdir -p DashPayiOS/Libraries

# Backup existing libraries (if any)
if [ -f "DashPayiOS/Libraries/libdash_spv_ffi_sim.a" ]; then
    echo -e "${YELLOW}Backing up existing libraries...${NC}"
    mkdir -p DashPayiOS/Libraries/backup
    cp DashPayiOS/Libraries/libdash_spv_ffi*.a DashPayiOS/Libraries/backup/ 2>/dev/null || true
    cp DashPayiOS/Libraries/libkey_wallet_ffi*.a DashPayiOS/Libraries/backup/ 2>/dev/null || true
fi

# Copy the new libraries
echo -e "${GREEN}Copying libraries to DashPayiOS/Libraries...${NC}"
cp "$RUST_DASHCORE_DIR/target/ios-simulator-universal/release/libdash_spv_ffi.a" DashPayiOS/Libraries/libdash_spv_ffi_sim.a
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios/release/libdash_spv_ffi.a" DashPayiOS/Libraries/libdash_spv_ffi_ios.a
cp "$RUST_DASHCORE_DIR/target/ios-simulator-universal/release/libkey_wallet_ffi.a" DashPayiOS/Libraries/libkey_wallet_ffi_sim.a
cp "$RUST_DASHCORE_DIR/target/aarch64-apple-ios/release/libkey_wallet_ffi.a" DashPayiOS/Libraries/libkey_wallet_ffi_ios.a

# Copy headers
echo -e "${GREEN}Copying header files...${NC}"
mkdir -p DashPayiOS/Libraries/include
cp "$RUST_DASHCORE_DIR/dash-spv-ffi/include/dash_spv_ffi.h" DashPayiOS/Libraries/include/ 2>/dev/null || \
    echo -e "${YELLOW}Warning: dash_spv_ffi.h header not found${NC}"
cp "$RUST_DASHCORE_DIR/key-wallet-ffi/include/key_wallet_ffi.h" DashPayiOS/Libraries/include/ 2>/dev/null || \
    echo -e "${YELLOW}Warning: key_wallet_ffi.h header not found${NC}"

# Create symlinks for active architecture (defaults to simulator for development)
echo -e "${GREEN}Creating symlinks for active architecture...${NC}"
cd DashPayiOS/Libraries
ln -sf libdash_spv_ffi_sim.a libdash_spv_ffi.a
ln -sf libkey_wallet_ffi_sim.a libkey_wallet_ffi.a
cd ../..

# Show library info
echo -e "${BLUE}Library information:${NC}"
echo "dash_spv_ffi libraries:"
ls -lah DashPayiOS/Libraries/libdash_spv_ffi*.a
echo ""
echo "key_wallet_ffi libraries:"
ls -lah DashPayiOS/Libraries/libkey_wallet_ffi*.a

echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
echo "Libraries have been updated in DashPayiOS/Libraries/:"
echo "  - libdash_spv_ffi_sim.a (simulator)"
echo "  - libdash_spv_ffi_ios.a (device)"
echo "  - libkey_wallet_ffi_sim.a (simulator)"
echo "  - libkey_wallet_ffi_ios.a (device)"
echo ""
echo "Symlinks created:"
echo "  - libdash_spv_ffi.a -> libdash_spv_ffi_sim.a"
echo "  - libkey_wallet_ffi.a -> libkey_wallet_ffi_sim.a"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Clean build folder in Xcode: Product → Clean Build Folder"
echo "2. Build and run the app"
echo ""
echo -e "${BLUE}To switch between simulator/device libraries:${NC}"
echo "cd DashPayiOS/Libraries"
echo "ln -sf libdash_spv_ffi_sim.a libdash_spv_ffi.a  # for simulator"
echo "ln -sf libdash_spv_ffi_ios.a libdash_spv_ffi.a  # for device"