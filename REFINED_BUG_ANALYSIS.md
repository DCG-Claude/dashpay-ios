# Refined Analysis of the Peer Count Bug

## Summary
After deeper investigation, the issue is likely **not** a simple `block_in_place` failure, but rather a timing or state synchronization issue between when connections are established and when stats are queried.

## Evidence Against My Original Theory

1. **block_in_place should work**: According to Tokio documentation, `block_in_place` is designed to work inside async contexts and should handle the runtime properly.

2. **No panics reported**: If `Handle::current()` was failing, we'd likely see panics or error messages, not just 0 returned.

3. **The code has been working**: This code has presumably been working in other contexts, suggesting the pattern itself isn't fundamentally broken.

## More Likely Scenarios

### Scenario 1: Race Condition
**Most Likely**: Stats are queried before connections are fully added to the pool.

Timeline:
1. Connection established at TCP level
2. Handshake completes
3. "SendHeaders2" message received (we see this in logs)
4. **Stats queried here** → returns 0
5. Connection added to pool (happens after)

Evidence:
- Pool logging shows: "Added connection to X, total peers: Y"
- This log doesn't appear before the stats debug

### Scenario 2: Different Pool Instance
The `network` object might not be the same instance that's receiving connections.

Possible causes:
- Multiple NetworkManager instances
- Mock vs real implementation confusion
- Cloning issues

### Scenario 3: Async Timing in FFI Layer
The FFI layer might be querying stats too early in the connection lifecycle.

The SPVClient.start() in Swift waits for connections, but it's checking stats in a loop. The first few checks might legitimately return 0.

## How to Verify

1. **Add more logging**:
   ```rust
   fn peer_count(&self) -> usize {
       println!("peer_count called");
       let pool = self.pool.clone();
       let result = tokio::task::block_in_place(move || {
           println!("Inside block_in_place");
           let count = tokio::runtime::Handle::current().block_on(pool.connection_count());
           println!("Connection count: {}", count);
           count
       });
       println!("peer_count returning: {}", result);
       result
   }
   ```

2. **Check connection timeline**:
   - Log when `add_connection` is called
   - Log when `peer_count` is called
   - Compare timestamps

3. **Verify pool identity**:
   - Add pool ID/address logging
   - Ensure same pool is used throughout

## Recommended Fix

Instead of changing the trait to async (which is a big change), consider:

1. **Add retry logic in Swift**: The SPVClient already waits up to 30 seconds. Ensure it's not giving up too early.

2. **Add connection count caching**: Update a cached count when connections are added/removed rather than querying async state synchronously.

3. **Fix the timing**: Ensure connections are fully registered before allowing stats queries.

## Conclusion

The issue is most likely a **timing problem** where stats are queried before connections are registered in the pool, not a fundamental issue with `block_in_place`. The fix should focus on ensuring proper synchronization between connection establishment and stats queries.