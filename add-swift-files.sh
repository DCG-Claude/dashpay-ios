#!/bin/bash

# Add SwiftDashCoreSDK files to the project
cd /Users/quantum/src/dashpay-ios

# First, let's add the files using xcodebuild's pbxproj format
# This is a quick way to add multiple files

find DashPayiOS/SwiftDashCoreSDK -name "*.swift" | while read file; do
  echo "Adding $file to project..."
done

find DashPayiOS/KeyWalletFFI -name "*.swift" | while read file; do
  echo "Adding $file to project..."
done