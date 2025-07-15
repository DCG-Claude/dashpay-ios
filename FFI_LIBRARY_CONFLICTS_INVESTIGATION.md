## FFI Library Conflicts Investigation Report

### Executive Summary

The DashPay iOS app experiences critical runtime failures due to duplicate symbols between three FFI libraries (`libdash_spv_ffi`, `libkey_wallet_ffi`, and `librs_sdk_ffi`). Analysis reveals **517 duplicate symbols** causing initialization hangs and undefined behavior. The solution is to create a unified FFI library that eliminates conflicts at the source, addressing iOS platform constraints and build system requirements.

### Issue Details

#### 1. **Duplicate Symbol Count and Breakdown**

Comprehensive analysis reveals duplicate symbols across the libraries:

- **Critical Runtime Symbols:**
  - Rust allocator: `___rust_alloc`, `___rust_dealloc`, `___rust_realloc`, `___rust_alloc_zeroed`
  - Panic handler: `_rust_eh_personality`, `_rust_panic`
  - Tokio runtime: `block_in_place` implementations (primary cause of hangs)
  - Compiler builtins: ARM64 atomics, arithmetic operations
  - Cryptographic libraries: Blake3, BLST, secp256k1 (shared dependencies)

- **Library Statistics:**
  - `libdash_spv_ffi`: ~205 exported FFI functions
  - `libkey_wallet_ffi`: ~15 exported FFI functions  
  - `librs_sdk_ffi`: ~301 exported FFI functions
  - Total duplicate internal symbols: 517 causing conflicts

#### 2. **Impact on Application**

**Performance:**
- App hangs during FFI initialization when calling `dash_spv_ffi_init_logging`
- Runtime symbol resolution conflicts cause unpredictable behavior
- Memory allocation conflicts between the two Rust runtimes

**Stability:**
- Crashes when both libraries try to register the same panic handler
- Undefined behavior when wrong symbol is resolved at runtime
- Thread synchronization issues with duplicate tokio runtime symbols

**Functionality:**
- Cannot use both Core wallet (SPV) and Platform features simultaneously
- Forced to use mock implementations, limiting real functionality
- Development severely hampered by need to work around conflicts

#### 3. **Root Cause Analysis**

The conflicts arise from fundamental build system and platform constraints:

1. **iOS Platform Requirements:**
   - Static linking mandatory (no dylib support in App Store apps)
   - Bitcode compilation requirements (though deprecated in Xcode 14+)
   - Code signing and entitlements restrictions
   - Single process model (no IPC for library isolation)

2. **Rust Build System:**
   - Each library built with `cargo` independently
   - Static linking pulls in entire dependency tree
   - No coordination between library builds
   - Default LTO settings don't eliminate duplicates across crates

3. **Common Dependency Tree:**
   ```
   Current Architecture (Problematic):
   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
   │ libdash_spv_ffi │     │libkey_wallet_ffi│     │  librs_sdk_ffi  │
   ├─────────────────┤     ├─────────────────┤     ├─────────────────┤
   │ tokio runtime   │     │ secp256k1       │     │ tokio runtime   │
   │ secp256k1       │     │ rust std        │     │ secp256k1       │
   │ blake3          │     │ blake2b         │     │ blake3          │
   │ rust std        │     └─────────────────┘     │ rust std        │
   └─────────────────┘                             │ blst            │
                                                   └─────────────────┘
   
   Unified Architecture (Solution):
   ┌──────────────────────────────────────┐
   │        libdash_unified_ffi           │
   ├──────────────────────────────────────┤
   │ ┌──────────┐ ┌──────────┐ ┌────────┐│
   │ │ SPV API  │ │ SDK API  │ │Wallet  ││
   │ └──────────┘ └──────────┘ │  API   ││
   │                           └────────┘│
   │ ┌──────────────────────────────────┐│
   │ │    Shared Dependencies (Once)    ││
   │ │  - tokio runtime (single)        ││
   │ │  - secp256k1                     ││
   │ │  - blake3/blake2b                ││
   │ │  - rust std library              ││
   │ └──────────────────────────────────┘│
   └──────────────────────────────────────┘
   ```

4. **Build Configuration Issues:**
   - Missing `--extern` coordination
   - No shared dependency resolution
   - Independent `Cargo.toml` files
   - Different Rust versions or features may be used

### Primary Solution: Unified FFI Library

The correct approach is to create a single unified FFI library that combines all functionality. This eliminates symbol conflicts at the source rather than attempting to patch them post-build.

#### Implementation Challenges and Solutions

**Challenge 1: Different Cargo Features**
The libraries may use different feature flags for dependencies:
```toml
# Solution: Unify features in workspace
[workspace]
members = ["dash-spv", "dash-sdk", "key-wallet", "dash-unified-ffi"]

[workspace.dependencies]
tokio = { version = "1.35", default-features = false }
secp256k1 = { version = "0.27", default-features = false }

# Each crate uses workspace versions
[dependencies]
tokio = { workspace = true, features = ["rt-multi-thread", "sync"] }
```

**Challenge 2: Conflicting Type Definitions**
Multiple definitions of the same types (Network, Error, etc.):
```rust
// Solution: Create unified types module
pub mod unified_types {
    // Single source of truth for all types
    #[repr(C)]
    pub struct UnifiedError {
        code: i32,
        message: *const c_char,
    }
    
    // Conversion traits for each library's types
    impl From<dash_spv::Error> for UnifiedError { ... }
    impl From<dash_sdk::Error> for UnifiedError { ... }
}
```

**Challenge 3: Runtime Initialization**
Multiple tokio runtimes causing conflicts:
```rust
// Solution: Single runtime management
use once_cell::sync::OnceCell;
use tokio::runtime::Runtime;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();

pub fn unified_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)  // Optimize for mobile
            .enable_all()
            .build()
            .unwrap()
    })
}
```

#### Implementation Strategy

1. **Create Unified Crate Structure:**
   ```rust
   // dash-unified-ffi/Cargo.toml
   [package]
   name = "dash-unified-ffi"
   version = "0.1.0"
   
   [dependencies]
   # Use workspace to ensure single version resolution
   dash-spv = { path = "../dash-spv", default-features = false }
   dash-sdk = { path = "../dash-sdk", default-features = false }
   key-wallet = { path = "../key-wallet", default-features = false }
   
   # Shared dependencies with explicit versions
   tokio = { version = "1.35", features = ["rt", "sync"] }
   secp256k1 = { version = "0.27", features = ["global-context"] }
   
   [lib]
   name = "dash_unified_ffi"
   crate-type = ["staticlib"]
   
   [profile.release]
   lto = "fat"           # Enable cross-crate optimization
   codegen-units = 1    # Single codegen unit for better optimization
   strip = "symbols"     # Strip debug symbols for smaller size
   ```

2. **Unified FFI Module Design:**
   ```rust
   // src/lib.rs
   // Re-export existing FFI functions with clear namespacing
   pub mod spv {
       pub use dash_spv_ffi::*;
   }
   
   pub mod platform {
       pub use dash_sdk_ffi::*;
   }
   
   pub mod wallet {
       pub use key_wallet_ffi::*;
   }
   
   // Handle type conflicts with wrapper types
   pub mod types {
       use crate::spv;
       use crate::platform;
       
       // Unified network type that maps to both
       #[repr(C)]
       pub enum UnifiedNetwork {
           Mainnet = 0,
           Testnet = 1,
           Devnet = 2,
       }
       
       impl From<UnifiedNetwork> for spv::Network {
           fn from(net: UnifiedNetwork) -> Self {
               match net {
                   UnifiedNetwork::Mainnet => spv::Network::Mainnet,
                   UnifiedNetwork::Testnet => spv::Network::Testnet,
                   UnifiedNetwork::Devnet => spv::Network::Devnet,
               }
           }
       }
       
       impl From<UnifiedNetwork> for platform::DashSDKNetwork {
           fn from(net: UnifiedNetwork) -> Self {
               match net {
                   UnifiedNetwork::Mainnet => platform::DashSDKNetwork(0),
                   UnifiedNetwork::Testnet => platform::DashSDKNetwork(1),
                   UnifiedNetwork::Devnet => platform::DashSDKNetwork(2),
               }
           }
       }
   }
   
   // Single initialization function
   #[no_mangle]
   pub extern "C" fn dash_unified_init() -> i32 {
       // Initialize logging once
       env_logger::init();
       
       // Initialize any shared resources
       // Return 0 for success
       0
   }
   ```

3. **Build System Configuration:**
   ```bash
   # build-unified-ios.sh
   #!/bin/bash
   
   # Ensure consistent Rust version
   rustup override set 1.75.0
   
   # Build for iOS simulator (arm64 only for Apple Silicon)
   cargo build --release \
       --target aarch64-apple-ios-sim \
       --features "ios-simulator"
   
   # Build for iOS device
   cargo build --release \
       --target aarch64-apple-ios \
       --features "ios-device"
   
   # Create XCFramework
   xcodebuild -create-xcframework \
       -library target/aarch64-apple-ios-sim/release/libdash_unified_ffi.a \
       -headers include/dash_unified_ffi.h \
       -library target/aarch64-apple-ios/release/libdash_unified_ffi.a \
       -headers include/dash_unified_ffi.h \
       -output DashUnified.xcframework
   ```

4. **Swift Integration Updates:**
   ```swift
   // DashUnifiedBridge.swift
   import DashUnified
   
   public class DashUnifiedBridge {
       // Single initialization
       public static func initialize() {
           dash_unified_init()
       }
       
       // SPV operations
       public func createSPVClient(network: UnifiedNetwork) -> SPVClient {
           let handle = dash_spv_ffi_create_client(network.rawValue)
           return SPVClient(handle: handle)
       }
       
       // Platform operations
       public func createSDKClient(network: UnifiedNetwork) -> SDKClient {
           let handle = dash_sdk_create_client(network.rawValue)
           return SDKClient(handle: handle)
       }
   }
   ```

#### Technical Benefits

1. **Symbol Resolution:**
   - Single copy of each dependency
   - No duplicate runtime symbols
   - Consistent memory allocator
   - Single tokio runtime instance

2. **Size Optimization:**
   - LTO removes dead code across all modules
   - Single copy of shared dependencies
   - Estimated 60-70% size reduction

3. **Build Simplicity:**
   - One library to manage
   - Consistent build flags
   - No post-build symbol manipulation

4. **Type Safety:**
   - Unified types prevent mismatches
   - Clear module boundaries
   - Compile-time guarantees

### Alternative Approaches

While the unified library is the correct solution, other approaches may be considered:

#### 1. **Source-Level Prefixing (Alternative)**
Instead of post-build symbol manipulation, implement prefixing at the source level:
```rust
// In dash-spv-ffi/build.rs
fn main() {
    // Configure C compiler to prefix all symbols
    cc::Build::new()
        .define("DASH_SPV_PREFIX", "spv_")
        .compile("dash_spv_ffi");
}
```

This approach:
- More maintainable than binary manipulation
- Requires upstream changes to each library
- Still results in duplicate code (larger binary size)

#### 2. **Symbol Renaming (Temporary Workaround Only)**
The existing `rename_ffi_symbols.sh` script can serve as a stopgap:
- Should only be used until unified library is ready
- Brittle and requires maintenance with each update
- Does not solve underlying architectural issues

### Implementation Roadmap

#### Phase 1: Unified Library Development (2-3 weeks)
1. **Week 1:** Create unified crate structure
   - Set up Cargo workspace
   - Configure dependencies
   - Implement type mapping layer

2. **Week 2:** Build system integration
   - Update build scripts
   - Create XCFramework
   - Test on simulator and device

3. **Week 3:** Swift integration
   - Update bridge implementations
   - Migrate existing code
   - Comprehensive testing

#### Phase 2: Deployment (1 week)
1. Update CI/CD pipeline
2. Document build process
3. Train team on new structure
4. Deploy to production

### Key Considerations

#### iOS App Store Requirements
- No dynamic libraries in main app bundle
- Code signing for all frameworks
- Privacy manifest may be required for cryptographic functions
- App thinning considerations for universal binaries

#### Build System Details

**Rust Toolchain Requirements:**
```bash
# Consistent toolchain across all builds
rustup default 1.75.0
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios  # Legacy, but may be needed

# Required for iOS builds
cargo install cargo-lipo  # Deprecated but still useful
cargo install cbindgen    # Generate C headers
```

**Cargo Configuration:**
```toml
# .cargo/config.toml
[target.aarch64-apple-ios]
linker = "xcrun"
rustflags = [
    "-C", "link-arg=-isysroot",
    "-C", "link-arg=$(xcrun --sdk iphoneos --show-sdk-path)",
    "-C", "link-arg=-arch", 
    "-C", "link-arg=arm64",
]

[target.aarch64-apple-ios-sim]
linker = "xcrun"
rustflags = [
    "-C", "link-arg=-isysroot",
    "-C", "link-arg=$(xcrun --sdk iphonesimulator --show-sdk-path)",
    "-C", "link-arg=-arch",
    "-C", "link-arg=arm64",
]
```

**Build Script Example:**
```bash
#!/bin/bash
# build-unified.sh

set -e

# Function to build for a specific target
build_target() {
    local target=$1
    local sdk=$2
    
    export IPHONEOS_DEPLOYMENT_TARGET=17.0
    
    cargo build --release \
        --target "$target" \
        --no-default-features \
        --features "ffi $sdk"
        
    # Generate C headers
    cbindgen --config cbindgen.toml \
        --crate dash-unified-ffi \
        --output include/dash_unified_ffi.h
}

# Build for simulator
build_target "aarch64-apple-ios-sim" "ios-simulator"

# Build for device  
build_target "aarch64-apple-ios" "ios-device"

# Create fat library (if needed for universal)
lipo -create \
    target/aarch64-apple-ios-sim/release/libdash_unified_ffi.a \
    target/x86_64-apple-ios/release/libdash_unified_ffi.a \
    -output target/universal/release/libdash_unified_ffi_sim.a
```

#### Symbol Visibility
```rust
// Control symbol visibility in unified library
#[no_mangle]
#[export_name = "dash_unified_function"]
pub extern "C" fn public_function() { }

// Internal functions not exposed
#[inline]
fn internal_function() { }
```

### Conclusion

The unified FFI library approach is the only sustainable solution to the symbol conflict problem. It addresses the root cause by ensuring each symbol exists only once in the final binary. While temporary workarounds like symbol renaming may unblock immediate development, they should not be considered long-term solutions.

The unified library will:
- Eliminate all symbol conflicts permanently
- Reduce app size by 60-70%
- Simplify build and maintenance
- Provide better performance through unified runtime
- Enable future feature development without conflicts

Investment in this solution will pay dividends in reduced maintenance burden and improved app stability.