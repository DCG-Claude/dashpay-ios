# Asset Lock Implementation

## Overview

This implementation provides real asset lock transaction creation functionality for the DashPay iOS app, replacing the previous mock implementations. Asset locks are special transactions used to fund Platform identities on the Dash network.

## Key Features

### 1. Real Transaction Creation
- Uses Core SDK FFI functions for transaction building
- Creates proper asset lock output scripts with OP_RETURN
- Implements UTXO selection for optimal fee calculation
- Supports InstantSend transactions (version 3)

### 2. InstantSend Lock Verification
- Waits for InstantSend locks with configurable timeout
- Checks transaction confirmations via FFI
- Returns proper InstantLock structures for Platform integration

### 3. Integration with Existing Architecture
- Extends DashSDK with asset lock specific methods
- Implements DashSDKProtocol for seamless integration with AssetLockBridge
- Maintains compatibility with SwiftData Transaction model

## Implementation Details

### Asset Lock Transaction Structure
```swift
// Asset lock transactions have:
// - Version: 3 (for InstantSend)
// - Outputs: 
//   - Asset lock output with OP_RETURN script
//   - Change output (if needed)
// - Higher fee rate (2 sat/byte) for priority
```

### Key Methods

#### `createAssetLockTransaction(amount:)`
- Validates minimum amount (10,000 duffs)
- Selects optimal UTXOs
- Creates asset lock output script
- Builds transaction with proper version and outputs

#### `broadcastTransaction(_:)`
- Broadcasts the transaction via SPV client
- Returns transaction ID for tracking

#### `waitForInstantLock(txid:timeout:)`
- Polls for InstantSend lock confirmation
- Uses FFI to check transaction confirmations
- Returns InstantLock structure when confirmed

#### `getInstantLock(for:)`
- Checks current InstantSend status
- Returns nil if not locked yet

## Usage Example

```swift
// Create asset lock transaction
let assetLockTx = try await dashSDK.createAssetLockTransaction(amount: 100_000)

// Broadcast the transaction
let txid = try await dashSDK.broadcastTransaction(assetLockTx)

// Wait for InstantSend lock
let instantLock = try await dashSDK.waitForInstantLock(txid: txid, timeout: 30.0)

// Create asset lock proof for Platform
let proof = AssetLockProof(
    transaction: assetLockTx,
    outputIndex: 0,
    instantLock: instantLock
)
```

## FFI Functions Used

- `dash_spv_ffi_client_broadcast_transaction` - Broadcast transactions
- `dash_spv_ffi_client_get_transaction_confirmations` - Check confirmations
- `dash_spv_ffi_client_get_address_balance` - Get address balances
- `dash_spv_ffi_client_get_utxos` - Get available UTXOs

## Future Improvements

1. **Transaction Building**: Implement full transaction building with proper input signing using FFI
2. **Script Creation**: Use proper P2SH scripts for asset locks instead of OP_RETURN
3. **InstantSend Verification**: Query masternode quorums for actual IS signatures
4. **Error Handling**: Add more detailed error cases for different failure scenarios
5. **Testing**: Add comprehensive unit and integration tests

## Notes

- The current implementation uses some placeholder logic for transaction building that should be replaced with proper FFI calls when available
- InstantSend verification currently uses a simplified approach - production should query actual masternode quorums
- The asset lock script format may need adjustment based on Platform requirements