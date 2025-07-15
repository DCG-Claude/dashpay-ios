# Platform SDK Migration Plan
## Migrating from Custom PlatformSDKWrapper to Official Swift SDK

### Executive Summary
This document outlines a detailed plan to migrate dashpay-ios from its custom `PlatformSDKWrapper` to the official platform-ios Swift SDK. The migration will improve maintainability, reduce code duplication, and ensure compatibility with future Platform updates.

## Current State Analysis

### Custom Implementation (PlatformSDKWrapper)
- **Location**: `/DashPayiOS/Shared/Bridges/PlatformSDKWrapper.swift`
- **Size**: 1,671 lines
- **Architecture**: Actor-based with async/await
- **FFI Module**: `DashSDKFFI`
- **Features**:
  - Identity management (create, fetch, fund, transfer)
  - Data contract operations
  - Document CRUD operations
  - Network status monitoring
  - Custom signer implementation
  - Asset lock proof handling

### Official SDK (platform-ios)
- **Location**: `/platform-ios/packages/swift-sdk/`
- **Architecture**: Class-based with delegates/callbacks
- **FFI Module**: `CDashSDKFFI`
- **Current Features**:
  - Basic identity fetching
  - Balance queries
  - Data contract fetching
  - Clean error handling

## Migration Phases

### Phase 1: Assessment and Preparation (1-2 weeks)

#### 1.1 Feature Gap Analysis
Create a comprehensive comparison matrix:

| Feature | PlatformSDKWrapper | Official SDK | Action Required |
|---------|-------------------|--------------|-----------------|
| Identity Creation | ✅ Full implementation | ❌ Not implemented | Add to SDK |
| Identity Funding | ✅ With asset lock | ❌ Not implemented | Add to SDK |
| Credit Transfers | ✅ Implemented | ❌ Not implemented | Add to SDK |
| Document Creation | ✅ Full CRUD | ❌ Not implemented | Add to SDK |
| Document Search | ✅ Query support | ❌ Not implemented | Add to SDK |
| Network Status | ✅ Monitoring | ❌ Not implemented | Add to SDK |
| Signer Integration | ✅ Custom callbacks | ❌ Not implemented | Add to SDK |

#### 1.2 Dependency Analysis
- Identify all components using `PlatformSDKWrapper`
- Map dependencies in `AssetLockBridge`
- Document integration points with Core wallet

#### 1.3 Test Coverage Assessment
- Review existing tests for Platform features
- Identify test gaps
- Plan test migration strategy

### Phase 2: SDK Enhancement (2-3 weeks)

#### 2.1 Fork and Enhance Official SDK
```bash
# Fork platform-ios repository
# Create feature branch: feature/dashpay-ios-compatibility
```

#### 2.2 Add Missing Core Features

**Identity Management**:
```swift
// Add to SDK.swift
public extension Identities {
    /// Create a new identity with funding
    func create(withFunding assetLock: AssetLockProof) async throws -> Identity
    
    /// Fund an existing identity
    func topUp(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity
    
    /// Transfer credits between identities
    func transferCredits(from: Identity, to: String, amount: UInt64) async throws -> TransferResult
}
```

**Document Operations**:
```swift
// New file: Documents.swift
public class Documents {
    private weak var sdk: SDK?
    
    /// Create a new document
    public func create(contractId: String, type: String, data: [String: Any]) async throws -> Document
    
    /// Fetch document by ID
    public func get(contractId: String, type: String, id: String) async throws -> Document?
    
    /// Update existing document
    public func update(_ document: Document, data: [String: Any]) async throws -> Document
    
    /// Delete document
    public func delete(_ document: Document) async throws
    
    /// Search documents with query
    public func search(contractId: String, type: String, query: DocumentQuery) async throws -> [Document]
}
```

**Signer Protocol**:
```swift
// New file: Signer.swift
public protocol DashPlatformSigner {
    func sign(data: Data, withKey publicKey: Data) async throws -> Data
    func canSign(forKey publicKey: Data) -> Bool
}

public extension SDK {
    /// Initialize with custom signer
    init(network: Network, signer: DashPlatformSigner) throws
}
```

#### 2.3 Add Actor-Based Wrappers (Optional)
To minimize changes in dashpay-ios:
```swift
// New file: ActorSDK.swift
@MainActor
public class ActorSDK {
    private let sdk: SDK
    
    public init(network: Network) throws {
        self.sdk = try SDK(network: network)
    }
    
    // Wrap all SDK methods with actor isolation
}
```

### Phase 3: Integration Layer (1-2 weeks)

#### 3.1 Create Compatibility Layer
Temporarily maintain both implementations:

```swift
// PlatformSDKProtocol.swift
protocol PlatformSDKProtocol {
    func fetchIdentity(id: String) async throws -> Identity
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity
    // ... all existing methods
}

// Make both implementations conform to protocol
extension PlatformSDKWrapper: PlatformSDKProtocol { }
extension OfficialSDKAdapter: PlatformSDKProtocol { }
```

#### 3.2 Create Adapter
```swift
// OfficialSDKAdapter.swift
actor OfficialSDKAdapter: PlatformSDKProtocol {
    private let sdk: SDK
    
    init(network: PlatformNetwork) throws {
        // Map PlatformNetwork to SDK.Network
        let sdkNetwork = mapNetwork(network)
        self.sdk = try SDK(network: sdkNetwork)
    }
    
    func fetchIdentity(id: String) async throws -> Identity {
        // Adapt official SDK response to existing Identity model
        guard let sdkIdentity = try await sdk.identities.get(id: id) else {
            throw PlatformError.identityNotFound
        }
        return Identity(from: sdkIdentity)
    }
    
    // Implement all protocol methods...
}
```

### Phase 4: Migration Implementation (2-3 weeks)

#### 4.1 Configuration Switch
Add feature flag for gradual rollout:

```swift
// AppConfiguration.swift
struct AppConfiguration {
    static var useOfficialPlatformSDK: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "UseOfficialPlatformSDK")
        #else
        return false // Start with custom in production
        #endif
    }
}
```

#### 4.2 Update AssetLockBridge
```swift
// AssetLockBridge.swift
class AssetLockBridge {
    private var platformSDK: PlatformSDKProtocol?
    
    init() {
        Task {
            if AppConfiguration.useOfficialPlatformSDK {
                self.platformSDK = try OfficialSDKAdapter(network: .testnet)
            } else {
                self.platformSDK = try PlatformSDKWrapper(network: .testnet)
            }
        }
    }
}
```

#### 4.3 Update UI Components
- Modify ViewModels to use protocol instead of concrete type
- Update error handling to match new SDK errors
- Adjust async patterns if needed

### Phase 5: Testing and Validation (2 weeks)

#### 5.1 Test Matrix

| Test Category | Test Cases | Priority |
|--------------|------------|----------|
| Identity Operations | Create, Fetch, Fund, Transfer | High |
| Document Operations | CRUD, Search, Pagination | High |
| Network Handling | Connection, Retry, Timeout | Medium |
| Error Scenarios | Invalid data, Network failures | High |
| Performance | Bulk operations, Memory usage | Medium |

#### 5.2 A/B Testing Strategy
```swift
// Enable gradual rollout
class FeatureFlags {
    static func platformSDKVersion(for userId: String) -> PlatformSDKVersion {
        let hash = userId.hash
        let percentage = abs(hash) % 100
        
        switch rolloutPhase {
        case 1: return percentage < 10 ? .official : .custom
        case 2: return percentage < 50 ? .official : .custom
        case 3: return percentage < 90 ? .official : .custom
        default: return .official
        }
    }
}
```

#### 5.3 Monitoring and Metrics
```swift
// Add analytics
class PlatformSDKMetrics {
    static func trackOperation(_ operation: String, sdk: String, success: Bool, duration: TimeInterval) {
        Analytics.track("platform_sdk_operation", properties: [
            "operation": operation,
            "sdk_version": sdk,
            "success": success,
            "duration_ms": duration * 1000
        ])
    }
}
```

### Phase 6: Cleanup and Optimization (1 week)

#### 6.1 Remove Custom Implementation
1. Delete `PlatformSDKWrapper.swift`
2. Remove custom FFI bindings
3. Update build configurations
4. Clean up unused dependencies

#### 6.2 Performance Optimization
- Profile new implementation
- Optimize memory usage
- Reduce unnecessary conversions

#### 6.3 Documentation Update
- Update README files
- Create migration guide for other consumers
- Document new patterns and best practices

## Risk Mitigation

### Technical Risks

1. **FFI Incompatibility**
   - **Risk**: Different FFI module names and structures
   - **Mitigation**: Create unified FFI wrapper if needed

2. **Feature Gaps**
   - **Risk**: Official SDK missing critical features
   - **Mitigation**: Contribute features upstream or maintain minimal extensions

3. **Performance Regression**
   - **Risk**: New SDK might be slower
   - **Mitigation**: Benchmark early, optimize critical paths

### Business Risks

1. **User Impact**
   - **Risk**: Bugs affecting production users
   - **Mitigation**: Gradual rollout with feature flags

2. **Timeline Delays**
   - **Risk**: Upstream SDK changes take longer
   - **Mitigation**: Start with adapter pattern, migrate gradually

## Success Criteria

1. **Functional Parity**: All existing features work with official SDK
2. **Performance**: No regression in operation times
3. **Stability**: Crash rate remains same or improves
4. **Code Reduction**: Remove 1,600+ lines of custom code
5. **Maintainability**: Easier updates with Platform releases

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Assessment | 1-2 weeks | None |
| SDK Enhancement | 2-3 weeks | Platform team collaboration |
| Integration Layer | 1-2 weeks | SDK enhancements complete |
| Migration | 2-3 weeks | Integration layer ready |
| Testing | 2 weeks | Migration complete |
| Cleanup | 1 week | Testing approved |
| **Total** | **9-13 weeks** | |

## Next Steps

1. **Immediate Actions**:
   - Schedule meeting with Platform SDK team
   - Create detailed feature comparison spreadsheet
   - Set up development environment for SDK work

2. **Week 1 Deliverables**:
   - Complete feature gap analysis
   - Create GitHub issues for missing features
   - Draft contribution guidelines for SDK

3. **Success Metrics Setup**:
   - Implement analytics for current implementation
   - Establish baseline performance metrics
   - Create dashboard for migration tracking

## Appendix A: Code Examples

### Current Usage (PlatformSDKWrapper)
```swift
let wrapper = try PlatformSDKWrapper(network: .testnet)
let identity = try await wrapper.createIdentity(with: assetLock)
```

### Target Usage (Official SDK)
```swift
let sdk = try SDK(network: .testnet)
let identity = try await sdk.identities.create(withFunding: assetLock)
```

### Adapter Pattern Example
```swift
// Allows gradual migration without changing call sites
let platform: PlatformSDKProtocol = AppConfig.useOfficialSDK ? 
    OfficialSDKAdapter() : PlatformSDKWrapper()
let identity = try await platform.createIdentity(with: assetLock)
```

## Appendix B: Testing Checklist

- [ ] All identity operations work correctly
- [ ] Document CRUD operations maintain data integrity
- [ ] Network failures are handled gracefully
- [ ] Memory usage is comparable or better
- [ ] Response times are within 10% of current
- [ ] Error messages are user-friendly
- [ ] Crash rate is not increased
- [ ] All UI flows work without modification