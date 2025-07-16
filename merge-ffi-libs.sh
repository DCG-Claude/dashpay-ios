#!/bin/bash

# Script to merge FFI libraries while avoiding duplicate symbols

set -e

LIBS_DIR="DashPayiOS/Libraries"
TEMP_DIR="/tmp/dash-ffi-merge"

echo "Creating merged FFI library..."

# Create temp directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Extract all object files from key_wallet_ffi
echo "Extracting key_wallet_ffi..."
cd "$TEMP_DIR"
ar x "$OLDPWD/$LIBS_DIR/libkey_wallet_ffi_sim.a"

# Find and keep only key_wallet_ffi specific object files
echo "Filtering key_wallet_ffi objects..."
mkdir key_wallet_objs
for obj in *.o; do
    # Check if this object file contains key_wallet_ffi symbols
    if nm "$obj" 2>/dev/null | grep -q "uniffi_key_wallet_ffi"; then
        mv "$obj" key_wallet_objs/
    fi
done

# Clean up non-key_wallet objects
rm -f *.o

# Go back to project root
cd "$OLDPWD"

# Create the merged library with only key_wallet_ffi objects
echo "Creating merged library..."
ar rcs "$LIBS_DIR/libkey_wallet_ffi_sim_filtered.a" "$TEMP_DIR"/key_wallet_objs/*.o

# Clean up
rm -rf "$TEMP_DIR"

echo "Merged library created at $LIBS_DIR/libkey_wallet_ffi_sim_filtered.a"
echo "This library contains only key_wallet_ffi specific symbols"