#!/bin/bash

# Alternative approach: Selective linking using object file extraction
# This extracts object files and creates custom libraries without duplicates

set -euo pipefail

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIBS_DIR="$PROJECT_ROOT/DashPayiOS/Libraries"
WORK_DIR="$PROJECT_ROOT/build/selective_linking"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to extract object files from library
extract_objects() {
    local lib="$1"
    local output_dir="$2"
    
    log_info "Extracting objects from $(basename "$lib")..."
    
    mkdir -p "$output_dir"
    cd "$output_dir"
    ar -x "$lib"
    cd - > /dev/null
    
    local count=$(find "$output_dir" -name "*.o" | wc -l)
    log_info "Extracted $count object files"
}

# Function to identify objects with duplicate symbols
find_duplicate_objects() {
    local dir1="$1"
    local dir2="$2"
    local output_file="$3"
    
    log_info "Finding objects with duplicate symbols..."
    
    > "$output_file"
    
    # For each object in dir1, check if it has symbols that exist in dir2
    for obj1 in "$dir1"/*.o; do
        [ -f "$obj1" ] || continue
        
        # Get symbols from this object
        local symbols1=$(nm -g "$obj1" 2>/dev/null | grep " T " | awk '{print $3}' | sort -u)
        
        for obj2 in "$dir2"/*.o; do
            [ -f "$obj2" ] || continue
            
            # Get symbols from other object
            local symbols2=$(nm -g "$obj2" 2>/dev/null | grep " T " | awk '{print $3}' | sort -u)
            
            # Find common symbols
            local common=$(comm -12 <(echo "$symbols1") <(echo "$symbols2") | wc -l)
            
            if [ "$common" -gt 0 ]; then
                echo "$(basename "$obj1") $(basename "$obj2") $common" >> "$output_file"
            fi
        done
    done
    
    local dup_count=$(wc -l < "$output_file")
    log_info "Found $dup_count object pairs with duplicate symbols"
}

# Function to create library excluding certain objects
create_filtered_library() {
    local objects_dir="$1"
    local exclude_list="$2"
    local output_lib="$3"
    
    log_info "Creating filtered library: $(basename "$output_lib")"
    
    # Create list of objects to include
    local include_list="$WORK_DIR/include_list.txt"
    find "$objects_dir" -name "*.o" -type f > "$include_list"
    
    # Remove excluded objects from list
    if [ -f "$exclude_list" ]; then
        while IFS= read -r exclude; do
            grep -v "$exclude" "$include_list" > "$include_list.tmp" || true
            mv "$include_list.tmp" "$include_list"
        done < "$exclude_list"
    fi
    
    # Create library from remaining objects
    local obj_count=$(wc -l < "$include_list")
    log_info "Including $obj_count object files"
    
    if [ "$obj_count" -gt 0 ]; then
        # Use libtool to create library
        libtool -static -o "$output_lib" $(cat "$include_list")
    else
        log_warn "No objects to include in library!"
    fi
}

# Main processing
main() {
    log_info "Starting selective linking approach..."
    
    # Clean and create work directory
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    
    # Libraries to process
    local spv_lib="$LIBS_DIR/libdash_spv_ffi_sim.a"
    local sdk_lib="$LIBS_DIR/DashSDK.xcframework/ios-arm64-simulator/librs_sdk_ffi.a"
    
    if [ ! -f "$spv_lib" ] || [ ! -f "$sdk_lib" ]; then
        log_error "Required libraries not found"
        exit 1
    fi
    
    # Extract objects from both libraries
    extract_objects "$spv_lib" "$WORK_DIR/spv_objects"
    extract_objects "$sdk_lib" "$WORK_DIR/sdk_objects"
    
    # Find duplicate objects
    find_duplicate_objects "$WORK_DIR/spv_objects" "$WORK_DIR/sdk_objects" "$WORK_DIR/duplicate_objects.txt"
    
    # Analyze duplicates
    log_info "Analyzing duplicate symbols..."
    
    # Group duplicates by common prefixes (blake3, blst, etc)
    grep -E "(blake3|blst)" "$WORK_DIR/duplicate_objects.txt" > "$WORK_DIR/crypto_duplicates.txt" || true
    grep -E "(compiler_builtins|rust_)" "$WORK_DIR/duplicate_objects.txt" > "$WORK_DIR/runtime_duplicates.txt" || true
    
    log_info "Crypto library duplicates: $(wc -l < "$WORK_DIR/crypto_duplicates.txt")"
    log_info "Runtime duplicates: $(wc -l < "$WORK_DIR/runtime_duplicates.txt")"
    
    # Strategy: Keep crypto libs in SPV, remove from SDK
    log_info "Creating exclude lists..."
    
    # For SDK: exclude crypto libraries
    awk '{print $2}' "$WORK_DIR/crypto_duplicates.txt" | sort -u > "$WORK_DIR/sdk_exclude.txt"
    
    # For SPV: keep everything (it's the core library)
    touch "$WORK_DIR/spv_exclude.txt"
    
    # Create filtered libraries
    create_filtered_library "$WORK_DIR/spv_objects" "$WORK_DIR/spv_exclude.txt" "$LIBS_DIR/libdash_spv_ffi_sim_selective.a"
    create_filtered_library "$WORK_DIR/sdk_objects" "$WORK_DIR/sdk_exclude.txt" "$LIBS_DIR/DashSDK.xcframework/ios-arm64-simulator/librs_sdk_ffi_selective.a"
    
    # Verify no duplicates remain
    log_info "Verifying filtered libraries..."
    
    local spv_syms="$WORK_DIR/spv_selective_symbols.txt"
    local sdk_syms="$WORK_DIR/sdk_selective_symbols.txt"
    
    nm -g "$LIBS_DIR/libdash_spv_ffi_sim_selective.a" 2>/dev/null | grep " T " | awk '{print $3}' | sort -u > "$spv_syms"
    nm -g "$LIBS_DIR/DashSDK.xcframework/ios-arm64-simulator/librs_sdk_ffi_selective.a" 2>/dev/null | grep " T " | awk '{print $3}' | sort -u > "$sdk_syms"
    
    local remaining=$(comm -12 "$spv_syms" "$sdk_syms" | wc -l)
    
    if [ "$remaining" -eq 0 ]; then
        log_info "✅ SUCCESS: No duplicate symbols in filtered libraries!"
    else
        log_warn "⚠️  WARNING: $remaining duplicate symbols still remain"
        comm -12 "$spv_syms" "$sdk_syms" | head -10
    fi
    
    log_info ""
    log_info "Selective linking complete!"
    log_info "Created libraries:"
    log_info "  - libdash_spv_ffi_sim_selective.a"
    log_info "  - librs_sdk_ffi_selective.a"
    log_info ""
    log_info "To use these libraries:"
    log_info "1. Update project.yml to use _selective libraries"
    log_info "2. Regenerate Xcode project"
    log_info "3. Test thoroughly - some symbols may be missing!"
}

# Run main
main "$@"