# FFI Stats Bug Analysis - Root Cause Found

## Bug Summary
The `dash_spv_ffi_client_get_stats` function returns 0 for `connected_peers` even though peers are actually connected. This prevents sync from starting in the iOS app.

## Root Cause
The bug is in the `MultiPeerManager::peer_count()` implementation in `dash-spv/src/network/multi_peer.rs:1080-1085`.

### The Problem Code
```rust
fn peer_count(&self) -> usize {
    let pool = self.pool.clone();
    tokio::task::block_in_place(move || {
        tokio::runtime::Handle::current().block_on(pool.connection_count())
    })
}
```

### Why It Fails
1. **Nested Runtime Blocking**: The FFI layer already uses `runtime.block_on()` to call `stats()`
2. Inside `stats()`, it calls `peer_count()` which tries to use `block_in_place` with `Handle::current()`
3. This creates nested blocking runtime calls, which can:
   - Panic if no runtime context is available
   - Return incorrect results (0) if the runtime handle can't be obtained
   - Cause deadlocks in certain async contexts

### Call Stack
```
dash_spv_ffi_client_get_stats (FFI)
  → client.runtime.block_on(async { ... })
    → spv_client.stats().await
      → self.network.peer_count() 
        → tokio::task::block_in_place(...)  // FAILS HERE
          → Handle::current().block_on(...)  // Can't get handle!
```

## The Fix

### Option 1: Make peer_count async (Best Solution)
Change the `NetworkManager` trait to make `peer_count` async:

```rust
// In network/mod.rs
#[async_trait]
pub trait NetworkManager: Send + Sync {
    // Change from:
    fn peer_count(&self) -> usize;
    // To:
    async fn peer_count(&self) -> usize;
}

// In network/multi_peer.rs
impl NetworkManager for MultiPeerManager {
    async fn peer_count(&self) -> usize {
        self.pool.connection_count().await
    }
}

// In client/mod.rs
pub async fn stats(&self) -> Result<SpvStats> {
    // Change from:
    stats.connected_peers = self.network.peer_count() as u32;
    // To:
    stats.connected_peers = self.network.peer_count().await as u32;
}
```

### Option 2: Cache peer count (Quick Fix)
Store the peer count in an atomic variable that's updated when connections change:

```rust
// In network/multi_peer.rs
pub struct MultiPeerManager {
    // Add:
    cached_peer_count: Arc<AtomicUsize>,
    // ... other fields
}

impl MultiPeerManager {
    // Update when connections change
    async fn update_peer_count(&self) {
        let count = self.pool.connection_count().await;
        self.cached_peer_count.store(count, Ordering::Relaxed);
    }
}

impl NetworkManager for MultiPeerManager {
    fn peer_count(&self) -> usize {
        self.cached_peer_count.load(Ordering::Relaxed)
    }
}
```

### Option 3: Use try_current (Workaround)
Check if a runtime exists before trying to use it:

```rust
fn peer_count(&self) -> usize {
    // Try to get current runtime handle
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        let pool = self.pool.clone();
        handle.block_on(pool.connection_count())
    } else {
        // Fall back to cached value or 0
        0
    }
}
```

## Why This Explains the Symptoms

1. **Logs show connections**: The Rust networking code successfully connects to peers
2. **Stats show 0**: The `peer_count()` method fails due to runtime issues and returns 0
3. **Sync doesn't start**: The sync logic checks stats and sees 0 peers, preventing sync

## Verification
The logs confirm this:
```
// Rust logs show successful peer connections:
INFO Peer 34.220.243.24:19999 sent SendHeaders2

// But FFI stats show:
FFI Stats Debug:
   - connected_peers: 0  // peer_count() failed!
```

## Recommended Fix
Implement Option 1 (make peer_count async) as it's the cleanest solution that properly handles async state access. This requires updating the NetworkManager trait but ensures correct behavior in all contexts.