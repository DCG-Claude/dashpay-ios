# Peer Configuration Fix

## Problem
The dashpay-ios app's sync functionality was not working while the rust-dashcore example app worked correctly. Investigation revealed that the key difference was in peer configuration.

## Root Cause
1. **dashpay-ios**: Was relying on the base SDK's `SPVClientConfiguration.testnet()` method which returns an empty peer list, expecting DNS seeds to work
2. **rust-dashcore example**: Uses hardcoded, known-good peer addresses that are guaranteed to be online

## Solution
Updated `WalletService.swift` to use the same hardcoded peer addresses as the working rust-dashcore example:

### Testnet Peers
```swift
private static let knownTestnetPeers = [
    "192.168.1.137:19999",
    "54.149.33.167:19999",
    "35.90.252.3:19999",
    "18.237.170.32:19999",
    "34.220.243.24:19999",
    "34.214.48.68:19999"
]
```

### Mainnet Peers
```swift
private static let knownMainnetPeers = [
    "142.93.154.186:9999",
    "8.219.251.8:9999",
    "165.22.30.195:9999",
    "65.109.114.212:9999",
    "188.40.21.248:9999",
    "66.42.58.154:9999"
]
```

## Changes Made

1. **WalletService.swift**:
   - Added static constants for known-good peer addresses
   - Updated `connect()` method to use hardcoded peers instead of relying on SDK defaults
   - Maintained the local/public peer toggle functionality

2. **SettingsConfigurationTests.swift**:
   - Updated tests that expected DNS seed addresses
   - Added comments explaining that peers are now configured in WalletService

## Benefits

1. **Reliability**: Using known-good peer addresses ensures consistent connectivity
2. **Faster Connection**: Direct IP addresses avoid DNS lookup delays
3. **Alignment**: Matches the working rust-dashcore implementation
4. **Maintainability**: Peer lists are centralized and easy to update

## Testing

Run the test script to verify configuration:
```bash
./test_peer_configuration.swift
```

## Future Improvements

1. Consider implementing a peer discovery mechanism that combines:
   - Hardcoded bootstrap peers (current solution)
   - DNS seeds as fallback
   - Peer exchange from connected nodes

2. Add peer health monitoring to automatically remove/replace failing peers

3. Consider loading peer lists from a configuration file for easier updates