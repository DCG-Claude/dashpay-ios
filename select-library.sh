#!/bin/bash

# Script to manually select the correct FFI library
# Usage: ./select-library.sh [sim|ios]

set -e

# Get the target from command line
TARGET="$1"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Navigate to Libraries directory
cd "$SCRIPT_DIR/DashPayiOS/Libraries"

if [ -z "$TARGET" ]; then
    echo "Usage: $0 [sim|ios]"
    echo "  sim - Configure for iOS Simulator"
    echo "  ios - Configure for iOS Device"
    exit 1
fi

echo "Selecting FFI libraries for target: $TARGET"

case "$TARGET" in
    "sim"|"simulator"|"iphonesimulator")
        echo "Configuring for iOS Simulator..."
        ln -sf libdash_spv_ffi_sim.a libdash_spv_ffi.a
        ln -sf libkey_wallet_ffi_sim.a libkey_wallet_ffi.a
        echo "✅ Linked simulator libraries"
        ;;
    "ios"|"device"|"iphoneos")
        echo "Configuring for iOS Device..."
        ln -sf libdash_spv_ffi_ios.a libdash_spv_ffi.a
        ln -sf libkey_wallet_ffi_ios.a libkey_wallet_ffi.a
        echo "✅ Linked device libraries"
        ;;
    *)
        echo "❌ Unknown target: $TARGET"
        echo "Usage: $0 [sim|ios]"
        exit 1
        ;;
esac

# Verify the symlinks
echo ""
echo "Current library configuration:"
ls -la libdash_spv_ffi.a
ls -la libkey_wallet_ffi.a

echo ""
echo "Remember to clean build folder in Xcode (⇧⌘K) after switching libraries!"