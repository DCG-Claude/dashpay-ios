---
allowed-tools:
  - Task
description: Run iOS app QA tests based on user story descriptions
---

# iOS QA Testing Command

This command spawns a sub-agent to perform comprehensive iOS app testing based on your test description.

## Usage
`/project:ios-qa "your test description"`

## Examples
- `/project:ios-qa "user can create a wallet and see their address"`
- `/project:ios-qa "user can create wallet, receive funds, and create a platform identity"`
- `/project:ios-qa "app launches without crashing and shows the onboarding screen"`

## Sub-Agent Task

The following Task agent will handle the entire iOS testing workflow:

```
Task: iOS QA Test Execution
Description: Perform iOS app testing for: $ARGUMENTS
Prompt: |
  You are an iOS QA testing agent. Your job is to test the DashPay iOS app based on this test scenario: $ARGUMENTS
  
  IMPORTANT: You must complete the ENTIRE testing workflow autonomously and return a comprehensive report.
  
  ## Your Testing Workflow:
  
  ### 1. Pre-flight Checks
  - Verify idb is installed: `which idb`
  - Check if simulator is booted: `xcrun simctl list devices | grep "(Booted)"`
  - If no simulator is booted, boot iPhone 15 and wait only until it appears as booted
  - Get DEVICE_UDID and connect idb
  
  ### 2. Build Preparation
  - Check if app is already built at: ./build/Build/Products/Debug-iphonesimulator/DashPay.app
  - If not built or build is stale:
    - Run `xcodegen` to generate project
    - Build with: `xcodebuild -project DashPayiOS.xcodeproj -scheme DashPayiOS -sdk iphonesimulator -configuration Debug -arch arm64 -derivedDataPath ./build build`
  
  ### 3. App Installation and Launch
  - Terminate any running instance: `xcrun simctl terminate <DEVICE_UDID> com.dash.wallet.ios`
  - Install app: `xcrun simctl install <DEVICE_UDID> ./build/Build/Products/Debug-iphonesimulator/DashPay.app`
  - Launch app: `xcrun simctl launch <DEVICE_UDID> com.dash.wallet.ios`
  - Immediately check UI state with `idb ui describe-all` to verify app launched
  
  ### 4. Test Execution
  Based on the test scenario, perform the required actions:
  
  - Use `idb ui describe-all` to understand current UI state (prefer this over screenshots for checking state)
  - Take screenshots ONLY for key moments and save to: /tmp/ios-qa-$(date +%s)/
  - Use `idb ui tap`, `idb ui swipe`, `idb ui text` for interactions
  - Monitor for errors with: `xcrun simctl spawn <DEVICE_UDID> log show --process DashPay --style compact --last 30s`
  
  ### 5. State Verification
  - Verify expected outcomes based on the test scenario
  - Check for error states, crashes, or unexpected behavior
  - Capture final state with screenshot if test passes/fails
  
  ### 6. Generate Report
  Return a structured report with:
  - Test Scenario: (the original test description)
  - Status: PASS/FAIL
  - Steps Performed: (list of actions taken)
  - Evidence: (screenshot paths, relevant log excerpts)
  - Issues Found: (any errors, crashes, or unexpected behavior)
  - Recommendations: (next steps or areas for investigation)
  
  ## Important Notes:
  - Create screenshot directory: `mkdir -p /tmp/ios-qa-$(date +%s)/`
  - Prefer `idb ui describe-all` over screenshots for state checking
  - Only take screenshots for important moments (initial state, errors, final state)
  - NO SLEEPING between operations - LLM processing time is sufficient for UI animations
  - If app shows "Initializing..." after multiple UI checks, then check logs for SDK errors
  - Bundle ID is: com.dash.wallet.ios
  - App name in logs is: DashPay
  
  ## Common UI Elements to Look For:
  - "Initializing..." - App is starting up
  - "Welcome" or "Get Started" - Onboarding screen
  - "Create Wallet" - Wallet creation flow
  - "Balance" or address display - Main wallet screen
  - Error dialogs - Red text or "Error", "Failed" messages
  
  Remember: Complete the ENTIRE workflow and return a comprehensive report. Do not ask for user input.
```