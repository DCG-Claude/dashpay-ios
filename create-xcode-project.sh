#!/bin/bash

# Script to create Xcode project for DashPay iOS
# This uses xcodegen to generate the project file

# First check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen not found. Installing via Homebrew..."
    brew install xcodegen
fi

# Create project.yml for xcodegen
cat > project.yml << 'EOF'
name: DashPayiOS
options:
  bundleIdPrefix: com.dash
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  
settings:
  base:
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    SWIFT_VERSION: "5.9"
    LIBRARY_SEARCH_PATHS: 
      - "$(PROJECT_DIR)/DashPayiOS/Libraries"
    FRAMEWORK_SEARCH_PATHS:
      - "$(PROJECT_DIR)/DashPayiOS/Libraries"
    OTHER_LDFLAGS:
      - "-lc++"
      - "-ObjC"
      
targets:
  DashPayiOS:
    type: application
    platform: iOS
    sources:
      - path: DashPayiOS
        excludes:
          - "**/*.md"
          - "**/Package.swift"
    dependencies:
      - framework: DashPayiOS/Libraries/libdash_spv_ffi_ios.a
        embed: false
      - framework: DashPayiOS/Libraries/DashSDK.xcframework
        embed: true
    settings:
      base:
        INFOPLIST_FILE: DashPayiOS/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.dash.wallet.ios
        PRODUCT_NAME: DashPay
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""
    postBuildScripts:
      - script: |
          # Select appropriate library for simulator/device
          if [ "${PLATFORM_NAME}" == "iphonesimulator" ]; then
              cp "${PROJECT_DIR}/DashPayiOS/Libraries/libdash_spv_ffi_sim.a" "${BUILT_PRODUCTS_DIR}/libdash_spv_ffi.a"
          else
              cp "${PROJECT_DIR}/DashPayiOS/Libraries/libdash_spv_ffi_ios.a" "${BUILT_PRODUCTS_DIR}/libdash_spv_ffi.a"
          fi
        name: "Copy FFI Library"
        
  DashPayiOSTests:
    type: bundle.unit-test
    platform: iOS
    sources: 
      - DashPayiOSTests
    dependencies:
      - target: DashPayiOS
    settings:
      TEST_HOST: "$(BUILT_PRODUCTS_DIR)/DashPay.app/DashPay"
      
  DashPayiOSUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - DashPayiOSUITests
    dependencies:
      - target: DashPayiOS
EOF

# Generate the Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo "Xcode project created successfully!"
echo "You can now open DashPayiOS.xcodeproj in Xcode"