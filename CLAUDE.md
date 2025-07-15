# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

### Project Setup
```bash
# Generate Xcode project from project.yml (required after fresh clone)
xcodegen

# Update FFI libraries from rust-dashcore (if needed)
./build-ios-libs.sh

# Manual library selection (automatically done by prebuild script)
./select-library.sh sim    # For simulator builds
./select-library.sh ios    # For device builds
```

### Build
```bash
# Build for simulator (Apple Silicon)
xcodebuild -project DashPayiOS.xcodeproj -scheme DashPayiOS -sdk iphonesimulator -configuration Debug -arch arm64 build

# Build with explicit derived data path (recommended for testing)
xcodebuild -project DashPayiOS.xcodeproj -scheme DashPayiOS \
    -sdk iphonesimulator -configuration Debug -arch arm64 \
    -derivedDataPath ./build build

# Build for device
xcodebuild -project DashPayiOS.xcodeproj -scheme DashPayiOS -sdk iphoneos -configuration Debug build

# Clean build
xcodebuild -project DashPayiOS.xcodeproj -scheme DashPayiOS clean

# Note: Clean build folder (⇧⌘K in Xcode) required after switching between simulator/device
```

### Tests
```bash
# Run unit tests
xcodebuild test -project DashPayiOS.xcodeproj -scheme DashPayiOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test
xcodebuild test -project DashPayiOS.xcodeproj -scheme DashPayiOS -only-testing:DashPayiOSTests/TestClassName/testMethodName -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'

# Run comprehensive feature tests
./comprehensive_testing_script.sh
```

### Lint
```bash
# SwiftLint (if installed)
swiftlint
swiftlint autocorrect
```

## Architecture Overview

### Project Structure
DashPay iOS is a unified wallet integrating Dash Core (Layer 1) and Dash Platform (Layer 2):

- **DashPayiOS/App/** - Application entry point and configuration
- **DashPayiOS/Core/** - Layer 1 wallet (transactions, addresses, SPV)
- **DashPayiOS/Platform/** - Layer 2 functionality (identities, documents, contracts)
- **DashPayiOS/Shared/** - Cross-layer components and bridges
- **DashPayiOS/Libraries/** - FFI libraries (libdash_spv_ffi, libkey_wallet_ffi, DashSDK.xcframework)

### App Configuration
- Bundle ID: `com.dash.wallet.ios`
- Product Name: `DashPay`
- Minimum iOS: 17.0
- Excluded simulator architectures: `x86_64` (Apple Silicon only)

### Key Components

#### FFI Integration
The app integrates Rust libraries via FFI:
- **DashSDK.xcframework** - Platform SDK with dash_sdk_* functions
- **libdash_spv_ffi_*.a** - SPV client libraries (sim/ios variants)
- **libkey_wallet_ffi_*.a** - HD wallet libraries (sim/ios variants)

Library selection is handled by `select-library.sh` script during build.

#### Cross-Layer Bridge
**AssetLockBridge** (Shared/Bridges/AssetLockBridge.swift) connects Core and Platform:
- Creates asset lock transactions for identity funding
- Implements `AssetLockProtocol` and `PlatformSDKProtocol`
- Uses actor pattern for thread safety

#### State Management
**UnifiedStateManager** (Shared/Models/UnifiedStateManager.swift) coordinates:
- Core wallet state
- Platform identities
- Cross-layer operations
- All UI updates via `@MainActor`

#### Network Configuration
Network types require careful mapping:
- `DashNetwork` (Core) - .mainnet, .testnet, .devnet, .regtest
- `DashSDKFFI.DashSDKNetwork` (Platform) - raw values 0, 1, 2
- `PlatformNetwork` provides the mapping layer

#### Network Security
Info.plist settings for network access:
- App allows arbitrary loads (`NSAllowsArbitraryLoads: true`)
- Local networking enabled for Dash node connections
- Bonjour services configured for testnet and mainnet

### Critical Implementation Details

#### Platform SDK Initialization
```swift
// Platform SDK requires DAPI addresses or falls back to mock mode
config.dapi_addresses = "https://testnet-addresses..."  // Required!
```

#### Type Visibility
Some types need explicit module prefixes:
- Use `DashSDKFFI.DashSDKNetwork` not `DashSDKNetwork`
- Use `KeyWalletFFI.Network.dash` not `.mainnet`

#### SwiftData Constraints
- Arrays must be stored as JSON or comma-separated strings
- All model operations must run on MainActor
- Models in Platform/Models/SwiftData/

#### Library Architecture
- Simulator: arm64 only (Apple Silicon)
- Device: arm64
- No x86_64 simulator support

### Common Development Tasks

#### Adding Platform Operation
1. Add to `PlatformSDKProtocol` in AssetLockBridge.swift
2. Implement in `PlatformSDKWrapper` using FFI pattern
3. Handle errors and memory cleanup
4. Return Swift-friendly types

#### Adding Core Feature
1. Add to appropriate service (WalletService, SPVClient, etc.)
2. Update UI in Core/Views/
3. Test with unit tests

#### Debugging FFI Issues
```swift
// Proper error logging
let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown"
print("🔴 FFI Error: \(errorMessage)")
```

### Testing

#### iOS QA Testing
For iOS app testing, **ALWAYS** use the Task tool:

```
Task: "iOS QA Test"
Description: "Test user story: [USER_STORY]"
Prompt: "Test scenario: [USER_STORY]

Please read and follow the instructions in .claude/prompts/ios_qa.md for the complete testing workflow."
```

**Trigger phrases requiring iOS QA Testing:**
- "test the iOS wallet [feature]"
- "test [app functionality]"
- "verify [app behavior]"
- Any iOS testing request

The iOS QA agent uses Mobile MCP tools to:
1. Build and launch app
2. Execute test scenarios
3. Capture screenshots
4. Return test reports

Detailed QA testing workflow is documented in `.claude/prompts/ios_qa.md`

#### Manual Testing with Mobile MCP

Use Mobile MCP tools for direct interaction:
- `mcp__mobile__mobile_use_default_device` - Select simulator
- `mcp__mobile__mobile_launch_app` - Launch with packageName="com.dash.wallet.ios"
- `mcp__mobile__mobile_take_screenshot` - Capture screen
- `mcp__mobile__mobile_list_elements_on_screen` - Get UI elements
- `mcp__mobile__mobile_click_on_screen_at_coordinates` - Tap elements
- `mcp__mobile__mobile_type_keys` - Enter text

#### Reset Simulator
```bash
# Reset specific simulator
DEVICE_UDID=$(xcrun simctl list devices | grep "(Booted)" | head -1 | grep -o '[A-F0-9-]\{36\}')
xcrun simctl erase $DEVICE_UDID

# Reset all simulators
xcrun simctl erase all
```

### Dependencies

- Xcode 15.0+
- iOS 17.0+ deployment target
- Swift 5.9+
- XcodeGen for project generation
- Local dependency: ../rust-dashcore/

### Known Issues

1. **Mock Implementations**: Some components use mocks pending full FFI integration
2. **Architecture Limitations**: Simulator builds only work on Apple Silicon
3. **Type Conflicts**: Some types require module prefixes as workarounds
4. **Threading**: SwiftData operations must use MainActor
5. **FFI Symbol Conflicts**: Use `scripts/selective_linking_approach.sh` for advanced troubleshooting

### Production Checklist

Before production:
1. Replace hardcoded testnet DAPI addresses
2. Implement proper key management
3. Add error recovery
4. Configure code signing
5. Remove debug prints
6. Add logging framework
7. Enable analytics/crash reporting