# Validating the Peer Count Theory

## Current Understanding

1. **Architecture**:
   - `DashSpvClient` has a field `stats: Arc<RwLock<SpvStats>>`
   - When `stats()` is called, it creates a `StatusDisplay` and gets a clone of stats
   - Then it updates `connected_peers` by calling `self.network.peer_count()`
   - `peer_count()` uses `tokio::task::block_in_place` with nested `block_on`

2. **Potential Issues**:

### Theory 1: Nested block_on fails (My Original Theory)
- `block_in_place` should work inside `block_on` according to tokio docs
- However, `Handle::current()` might fail if runtime context isn't properly set
- This would cause a panic or return 0

### Theory 2: Connection Pool is Empty
- The `pool.connection_count()` might genuinely return 0
- Connections might be established but not added to the pool
- Or connections are added after stats are queried

### Theory 3: Wrong Network Manager
- Maybe `self.network` is a mock or different implementation
- The real connections might be in a different manager

### Theory 4: Timing Issue
- Stats are queried before connections are fully established
- The "SendHeaders2" log happens after handshake but before pool update

## How to Validate

### Test 1: Check if block_in_place actually fails
```rust
// The peer_count implementation
fn peer_count(&self) -> usize {
    let pool = self.pool.clone();
    tokio::task::block_in_place(move || {
        tokio::runtime::Handle::current().block_on(pool.connection_count())
    })
}
```

Issues with this code:
- `Handle::current()` requires being inside a tokio runtime
- `block_in_place` moves the current task to a blocking thread
- The combination might lose runtime context

### Test 2: Check connection pool state
Need to verify:
- When connections are added to the pool
- If the pool is the same one being queried
- If there's a delay between connection and pool update

### Test 3: Check the actual error
The code doesn't handle errors from `Handle::current()` - it would panic.
But we're seeing 0, not a panic, which suggests:
- Either the error is caught somewhere
- Or `connection_count()` is returning 0

## Alternative Explanations

### 1. Mock Network Manager
Check if FFI creates a mock network manager instead of real one

### 2. Connection State Machine
Connections might go through states:
- Connecting
- Handshaking  
- Connected (logs show "SendHeaders2")
- Added to pool (this might be missing)

### 3. Different Runtime Contexts
FFI runtime vs SPV client runtime might not share state properly

## Next Steps to Validate

1. Add logging to `peer_count()` to see if it's called and what it returns
2. Add logging to `pool.connection_count()` to see the actual count
3. Check when connections are added to the pool vs when "SendHeaders2" is logged
4. Verify which NetworkManager implementation is being used

## Most Likely Cause

Based on the evidence:
- Logs show successful connections ("SendHeaders2")
- Stats show 0 peers
- No panic/crash reported

The most likely issue is **Theory 2**: The connection pool is empty when queried, even though connections exist. This could be due to:
- Connections not being added to the pool properly
- Pool being queried before connections are registered
- Different pool instance being queried

The `block_in_place` issue (Theory 1) is less likely because:
- It would likely cause a panic, not return 0
- The tokio documentation suggests it should work
- The code has been working in other contexts