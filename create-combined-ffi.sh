#!/bin/bash

# Script to create a combined FFI library without symbol conflicts

set -e

LIBS_DIR="DashPayiOS/Libraries"
TEMP_DIR="/tmp/dash-ffi-combine"

echo "Creating combined FFI library..."

# Clean up any existing temp directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Extract all object files
echo "Extracting object files..."
cd "$TEMP_DIR"

# Store original path
ORIG_DIR="$OLDPWD"

# Extract dash_spv_ffi
mkdir dash_spv
cd dash_spv
ar x "$ORIG_DIR/$LIBS_DIR/libdash_spv_ffi_sim_renamed.a"
cd ..

# Extract key_wallet_ffi
mkdir key_wallet
cd key_wallet
ar x "$ORIG_DIR/$LIBS_DIR/libkey_wallet_ffi_sim.a"
cd ..

# Extract rs_sdk_ffi
mkdir rs_sdk
cd rs_sdk
ar x "$ORIG_DIR/$LIBS_DIR/DashSDK.xcframework/ios-arm64-simulator/librs_sdk_ffi_renamed.a"
cd ..

# Collect unique object files
echo "Collecting unique object files..."
mkdir combined

# Copy dash_spv_ffi objects
cp dash_spv/*.o combined/ 2>/dev/null || true

# Copy only key_wallet_ffi specific objects (avoid duplicates)
for obj in key_wallet/*.o; do
    basename=$(basename "$obj")
    if [[ "$basename" == *"key_wallet"* ]] || [[ "$basename" == *"bip"* ]]; then
        if [ ! -f "combined/$basename" ]; then
            cp "$obj" combined/
        fi
    fi
done

# Copy only rs_sdk_ffi specific objects
for obj in rs_sdk/*.o; do
    basename=$(basename "$obj")
    if [[ "$basename" == *"rs_sdk"* ]] || [[ "$basename" == *"platform"* ]]; then
        if [ ! -f "combined/$basename" ]; then
            cp "$obj" combined/
        fi
    fi
done

# Go back to project root
cd "$OLDPWD"

# Create the combined library
echo "Creating combined library..."
ar rcs "$LIBS_DIR/libdash_combined_ffi_sim.a" "$TEMP_DIR"/combined/*.o

# Check the result
echo "Combined library created. Contents:"
ar t "$LIBS_DIR/libdash_combined_ffi_sim.a" | wc -l
echo "object files"

# Clean up
rm -rf "$TEMP_DIR"

echo "Done! Combined library created at $LIBS_DIR/libdash_combined_ffi_sim.a"