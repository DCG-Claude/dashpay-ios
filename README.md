# DashPay iOS Application

This repository contains the source code for the DashPay iOS application.

## Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Build Instructions](#build-instructions)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Production Build](#production-build)

## Features

This section will describe the key features and functionalities of the DashPay iOS application. Please update this section with a detailed list of features as they are implemented or become stable.

## Prerequisites
- Xcode 15.0 or later
- iOS 17.0 SDK
- Swift 5.9+

## Build Instructions

### 1. Open Project
```bash
cd /Users/quantum/src/dashpay-ios
open DashPayiOS.xcodeproj
```

### 2. Configure Framework Search Paths
In Xcode:
1. Select the DashPayiOS project in navigator
2. Select the DashPayiOS target
3. Go to Build Settings tab
4. Search for "Framework Search Paths"
5. Add: `$(SRCROOT)/DashPayiOS/Libraries`

### 3. Configure Library Search Paths
1. In Build Settings, search for "Library Search Paths"
2. Add these paths:
   - `$(SRCROOT)/DashPayiOS/Libraries`
   - `$(SRCROOT)/DashPayiOS/Libraries/DashSDK.xcframework/ios-arm64` (for device)
   - `$(SRCROOT)/DashPayiOS/Libraries/DashSDK.xcframework/ios-arm64-simulator` (for simulator)

### 4. Link Binary Libraries
1. Go to Build Phases tab
2. Expand "Link Binary With Libraries"
3. Add:
   - libdash_spv_ffi_ios.a (for device builds)
   - libdash_spv_ffi_sim.a (for simulator builds)
   - librs_sdk_ffi.a (from DashSDK.xcframework)

### 5. Configure Module Map
1. In Build Settings, search for "Import Paths"
2. Add: `$(SRCROOT)/DashPayiOS/Libraries/DashSDK.xcframework/ios-arm64/Headers`

### 6. Add Swift Package Dependencies
The project already references local packages:
- SwiftDashCoreSDK (../rust-dashcore/swift-dash-core-sdk)
- KeyWalletFFI (../rust-dashcore/key-wallet-ffi)

Ensure these packages build successfully first.

### 7. Select Scheme and Build
1. Select "DashPayiOS" scheme
2. Select target device (simulator or real device)
3. Press Cmd+B to build

## Testing

### Unit Tests
```bash
# Run from Xcode
Cmd+U
```

### UI Tests
1. Select DashPayiOSUITests scheme
2. Press Cmd+U

## Troubleshooting

### Module Not Found
If you get "module 'DashSDKFFI' not found":
1. Check that module.modulemap exists in Headers directory
2. Verify Import Paths setting includes the Headers directory
3. Clean build folder (Cmd+Shift+K) and rebuild

### Undefined Symbols
If you get linker errors:
1. Verify .a files are added to Link Binary With Libraries
2. Check Library Search Paths includes the correct directories
3. Ensure architecture matches (arm64 for device, x86_64/arm64 for simulator)

### Swift Package Errors
If local packages fail to resolve:
1. Check that paths in Package.swift are correct
2. Build the dependencies separately first
3. Use File > Packages > Reset Package Caches

## Production Build

For production builds:
1. Set build configuration to Release
2. Enable optimizations
3. Remove mock implementations
4. Implement proper error handling
5. Add proper logging
6. Configure code signing
