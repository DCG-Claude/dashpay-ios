## State Management Chaos Investigation Report

### Executive Summary

The DashPay iOS codebase exhibits significant state management issues with multiple sources of truth, circular dependencies, and unclear data flow patterns. The architecture attempts to bridge Core (Layer 1) and Platform (Layer 2) functionality but lacks a coherent state management strategy.

### Complete State Management Flow

```
┌─────────────────┐
│  UnifiedAppState│ ◄── Top-level App State (Entry Point)
└────────┬────────┘
         │ Creates & Owns
         ▼
    ┌────────────────────────────────────────────────┐
    │                                                │
    ▼                ▼                               ▼
┌─────────────┐  ┌──────────┐           ┌─────────────────────┐
│WalletService│  │ AppState │           │UnifiedStateManager  │
│  (Core L1)  │  │(Platform)│           │  (Cross-Layer)      │
└─────┬───────┘  └────┬─────┘           └─────────┬───────────┘
      │               │                             │
      │               │                             │ 
┌─────▼───────┐  ┌────▼─────┐           ┌─────────▼───────────┐
│  SPVClient  │  │PlatformSDK│           │  AssetLockBridge   │
│   Events    │  │  Wrapper  │           │ CrossLayerBridge   │
└─────┬───────┘  └────┬─────┘           └─────────┬───────────┘
      │               │                             │
┌─────▼────────────────▼────────────────────────────▼────────────┐
│                    SwiftData Models                            │
│  HDWallet, HDAccount, HDWatchedAddress, Balance,              │
│  Transaction, PersistentIdentity, PersistentDocument, etc.    │
└────────┬──────────────────────────────────────┬────────────────┘
         │                                      │
    ┌────▼─────────┐                    ┌──────▼──────────┐
    │NetworkMonitor│                    │NotificationCenter│
    │  (Reachability)                   │  (System Events) │
    └──────────────┘                    └─────────────────┘

Temporal Flow:
1. App Launch → UnifiedAppState.initialize()
2. Parallel: WalletService.setup() | AppState.initialize()
3. SPVClient connects → Emits events → WalletService handles
4. NetworkMonitor changes → Triggers reconnection attempts
5. SwiftData saves → Triggers UI updates → May cause re-queries
6. Async operations complete → Update multiple state locations
```

### Identified State Storage Locations

1. **UnifiedAppState** (`DashPayApp.swift`)
   - Top-level orchestrator
   - Owns: WalletService, AppState, UnifiedStateManager
   - Manages initialization sequence
   - Published properties: isInitialized, error

2. **WalletService** (`Core/Services/WalletService.swift`)
   - Core wallet state management
   - Published properties: activeWallet, activeAccount, syncProgress, isConnected, isSyncing, watchAddressErrors
   - Direct SwiftData access via modelContext
   - Manages SDK instance lifecycle
   - Handles SPV events and balance updates

3. **AppState** (`Platform/AppState.swift`)
   - Platform state management
   - Published properties: identities, contracts, tokens, documents, isLoading, showError
   - Owns: sdk, coreSDK, platformSDK, assetLockBridge
   - Manages DataManager instance

4. **UnifiedStateManager** (`Shared/Models/UnifiedStateManager.swift`)
   - Cross-layer state coordination
   - Published properties: unifiedBalance, wallets, identities, isPlatformSynced, isLoading
   - References: coreSDK, platformWrapper, assetLockBridge, crossLayerBridge
   - Attempts to unify Core and Platform balances

5. **SwiftData Models** (Core/Models/, Platform/Models/SwiftData/)
   - Persistent storage layer
   - HDWallet, HDAccount, HDWatchedAddress
   - PersistentIdentity, PersistentDocument, PersistentContract
   - Transaction, Balance, UTXO

### Circular Dependencies Identified

1. **UnifiedAppState ↔ Services**
   ```
   UnifiedAppState → WalletService → SDK → Events → WalletService
                  ↘ AppState → SDK → PlatformWrapper ↗
                   ↘ UnifiedStateManager ←───────────┘
   ```

2. **SDK Management Confusion**
   - UnifiedAppState creates coreSDK
   - AppState also creates its own coreSDK instance
   - WalletService manages its own sdk instance
   - Multiple SDK instances for the same functionality

3. **State Update Loops**
   ```
   WalletService.updateAccountBalance() 
     → Updates SwiftData Balance 
     → Triggers @Published changes
     → UnifiedStateManager observes changes
     → Updates its own balance state
     → May trigger WalletService updates
   ```

4. **Cross-Layer Bridge Dependencies**
   ```
   AssetLockBridge → needs both Core and Platform SDKs
   CrossLayerBridge → needs AssetLockBridge
   UnifiedStateManager → needs both bridges
   AppState → creates bridges
   ```

5. **Notification-Based Cycles**
   ```
   SPVClient → Posts notification → WalletService observes
     → Updates state → Triggers UI update
     → UI queries WalletService → May trigger SPV operations
     → SPVClient posts more notifications
   ```

6. **Persistence Layer Triggers**
   ```
   SwiftData save() → Triggers relationship updates
     → Fires willSet/didSet on models
     → Updates computed properties
     → Triggers more SwiftData operations
     → Potential infinite save loop
   ```

7. **Closure/Completion Handler Cycles**
   ```
   WalletService.syncWallet { completion in
     UnifiedStateManager.updateState {
       WalletService.refreshBalance { // Circular reference
         completion()
       }
     }
   }
   ```

8. **NetworkMonitor State Cascades**
   ```
   NetworkMonitor.pathUpdateHandler → isConnected changes
     → WalletService reconnects → Updates sync state
     → UnifiedStateManager reacts → May trigger network check
     → NetworkMonitor updates again
   ```

### Conflicting Sources of Truth

1. **Balance Information**
   - WalletService: `activeAccount.balance` (SwiftData)
   - UnifiedStateManager: `unifiedBalance` (computed)
   - HDWallet model: `totalBalance` (computed from accounts)
   - Individual HDWatchedAddress: `balance` property

2. **Identity Management**
   - AppState: `identities` array
   - UnifiedStateManager: `identities` array
   - IdentityService: `cachedIdentities` dictionary
   - DataManager: PersistentIdentity in SwiftData

3. **Network Configuration**
   - WalletService: Uses DashNetwork enum
   - AppState: Uses PlatformNetwork enum
   - Multiple conversions between network types

4. **Sync State**
   - WalletService: `syncProgress`, `detailedSyncProgress`, `isSyncing`
   - UnifiedStateManager: Removed duplicate tracking but still references WalletService
   - SyncState model in SwiftData

### Performance Implications

1. **Redundant Data Storage**
   - Same data stored in multiple places
   - Frequent conversions between model types
   - Unnecessary SwiftData saves

2. **Update Cascades**
   - Single balance update triggers multiple state changes
   - Published properties cause unnecessary UI refreshes
   - SwiftData relationship updates are inefficient

3. **Memory Overhead**
   - Multiple caches (IdentityService, AppState, UnifiedStateManager)
   - Duplicate SDK instances
   - Large in-memory state objects

4. **Thread Safety Issues**
   - Mix of @MainActor and async/await
   - SwiftData operations must be on MainActor
   - Potential race conditions in state updates

### Mobile-Specific Performance Considerations

1. **Battery Impact**
   - Continuous SPV sync drains battery
   - Redundant network requests from multiple state managers
   - Excessive SwiftData saves trigger disk I/O
   - Background refresh without proper scheduling

2. **Network Efficiency**
   - Multiple SDK instances may create duplicate connections
   - No request coalescing or batching
   - NetworkMonitor triggers aggressive reconnection attempts
   - Missing caching for Platform queries

3. **App Launch Time**
   - Sequential initialization of multiple state managers
   - SwiftData migration on every launch
   - No lazy loading of non-critical components
   - SDK initialization blocks UI

4. **Memory Pressure Handling**
   - No response to memory warnings
   - Unbounded caches in IdentityService
   - Large SwiftData result sets kept in memory
   - No image/data purging strategy

### Detailed Refactoring Plan

#### Phase 1: Establish Single Source of Truth

1. **Consolidate SDK Management with Actors**
   ```swift
   // Use Swift actors for thread-safe SDK management
   actor SDKCoordinator {
       static let shared = SDKCoordinator()
       private var coreSDK: DashSDK?
       private var platformSDK: PlatformSDKWrapper?
       
       func initialize(network: UnifiedNetwork) async throws {
           // Thread-safe initialization
           self.coreSDK = try await DashSDK.create(network: network.dashNetwork)
           self.platformSDK = try await PlatformSDKWrapper(network: network.platformNetwork)
       }
       
       func performCoreOperation<T>(_ operation: (DashSDK) async throws -> T) async throws -> T {
           guard let sdk = coreSDK else { throw SDKError.notInitialized }
           return try await operation(sdk)
       }
   }
   ```

2. **Protocol-Oriented State Management**
   ```swift
   // Define state protocols for testability
   protocol WalletStateProtocol: AnyObject {
       var wallets: [HDWallet] { get }
       var activeWallet: HDWallet? { get }
       func updateBalance(for walletId: UUID, balance: UInt64) async
   }
   
   protocol PlatformStateProtocol: AnyObject {
       var identities: [Identity] { get }
       func createIdentity(funding: AssetLock) async throws -> Identity
   }
   ```

3. **SwiftData as Primary Source of Truth**
   ```swift
   @MainActor
   final class UnifiedStateContainer: ObservableObject {
       private let modelContainer: ModelContainer
       
       // Computed properties derived from SwiftData
       var wallets: [HDWallet] {
           let descriptor = FetchDescriptor<HDWallet>(sortBy: [SortDescriptor(\.createdAt)])
           return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
       }
       
       // Single write path through SwiftData
       func updateWalletBalance(_ walletId: UUID, balance: UInt64) async {
           guard let wallet = fetchWallet(id: walletId) else { return }
           wallet.updateBalance(balance)
           try? modelContainer.mainContext.save()
       }
   }
   ```

#### Phase 2: iOS-Native Architecture Options

##### Option 1: The Composable Architecture (TCA) - Recommended
```swift
// TCA provides Redux-like benefits with iOS idioms
struct AppReducer: ReducerProtocol {
    struct State: Equatable {
        var wallets: IdentifiedArrayOf<Wallet>
        var identities: IdentifiedArrayOf<Identity>
        var syncProgress: SyncProgress?
        var networkStatus: NetworkStatus
    }
    
    enum Action: Equatable {
        case onAppear
        case walletResponse(TaskResult<[Wallet]>)
        case syncProgressUpdated(SyncProgress)
        case networkStatusChanged(NetworkStatus)
        case createWalletTapped
    }
    
    @Dependency(\.walletClient) var walletClient
    @Dependency(\.networkMonitor) var networkMonitor
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    for await status in networkMonitor.statusStream() {
                        await send(.networkStatusChanged(status))
                    }
                }
            case let .walletResponse(.success(wallets)):
                state.wallets = IdentifiedArray(uniqueElements: wallets)
                return .none
            // ... handle other actions
            }
        }
    }
}
```

##### Option 2: MVVM with Combine
```swift
// Traditional MVVM with reactive bindings
@MainActor
final class WalletViewModel: ObservableObject {
    @Published private(set) var wallets: [Wallet] = []
    @Published private(set) var syncProgress: Double = 0
    @Published private(set) var isLoading = false
    
    private let walletService: WalletServiceProtocol
    private let networkMonitor: NetworkMonitor
    private var cancellables = Set<AnyCancellable>()
    
    init(walletService: WalletServiceProtocol, networkMonitor: NetworkMonitor) {
        self.walletService = walletService
        self.networkMonitor = networkMonitor
        
        // Reactive bindings
        networkMonitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] isConnected in
                if isConnected {
                    Task { await self?.refreshWallets() }
                }
            }
            .store(in: &cancellables)
    }
}
```

##### Option 3: Actor-Based State Management
```swift
// Leverage Swift concurrency for state isolation
actor AppStateActor {
    private var wallets: [UUID: Wallet] = [:]
    private var identities: [UUID: Identity] = [:]
    private let modelContext: ModelContext
    
    private var observers: [UUID: CheckedContinuation<StateUpdate, Never>] = [:]
    
    func observeStateUpdates() -> AsyncStream<StateUpdate> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }
    
    func updateWallet(_ wallet: Wallet) async {
        wallets[wallet.id] = wallet
        await notifyObservers(.walletUpdated(wallet))
        await persistToSwiftData(wallet)
    }
}
```

##### Option 4: SwiftData-First Architecture
```swift
// Embrace SwiftData as the source of truth
@MainActor
final class SwiftDataStateManager: ObservableObject {
    private let modelContainer: ModelContainer
    
    // Query-based state derived from SwiftData
    @Query(sort: \HDWallet.createdAt) private var wallets: [HDWallet]
    @Query(filter: #Predicate<Transaction> { $0.timestamp > Date.now.addingTimeInterval(-86400) })
    private var recentTransactions: [Transaction]
    
    // Minimal in-memory state for UI
    @Published var syncProgress: Double = 0
    @Published var networkStatus: NetworkStatus = .disconnected
    
    // All mutations go through SwiftData
    func createWallet(mnemonic: [String]) async throws {
        let context = modelContainer.mainContext
        let wallet = HDWallet(mnemonic: mnemonic)
        context.insert(wallet)
        try context.save()
        
        // Side effects handled separately
        await notifyWalletCreated(wallet)
    }
}
```

#### Phase 3: Simplify Service Layer

1. **Protocol-Based Service Architecture**
   ```swift
   // Define clear service boundaries
   protocol WalletServiceProtocol: Actor {
       func createWallet(mnemonic: [String]) async throws -> HDWallet
       func syncWallet(_ wallet: HDWallet) async throws
       func observeSyncProgress() -> AsyncStream<SyncProgress>
   }
   
   // Implementation with actor isolation
   actor WalletService: WalletServiceProtocol {
       private let sdkCoordinator: SDKCoordinator
       private let modelContainer: ModelContainer
       
       func createWallet(mnemonic: [String]) async throws -> HDWallet {
           // Pure business logic, no state management
           let wallet = try await sdkCoordinator.performCoreOperation { sdk in
               try await sdk.createWallet(mnemonic: mnemonic)
           }
           
           // Persist through SwiftData
           await MainActor.run {
               modelContainer.mainContext.insert(wallet)
               try? modelContainer.mainContext.save()
           }
           
           return wallet
       }
   }
   ```

2. **Event-Driven Updates**
   ```swift
   // Use AsyncSequence for reactive updates
   extension SPVClient {
       func syncEvents() -> AsyncStream<SyncEvent> {
           AsyncStream { continuation in
               let observer = NotificationCenter.default.addObserver(
                   forName: .spvSyncProgress,
                   object: nil,
                   queue: .main
               ) { notification in
                   if let progress = notification.userInfo?["progress"] as? Double {
                       continuation.yield(.progress(progress))
                   }
               }
               
               continuation.onTermination = { _ in
                   NotificationCenter.default.removeObserver(observer)
               }
           }
       }
   }
   ```

#### Phase 4: Optimize SwiftData Usage

1. **Batch Operations with Transactions**
   ```swift
   extension ModelContext {
       func performBatchUpdate<T>(_ updates: @escaping (ModelContext) throws -> T) async throws -> T {
           try await MainActor.run {
               let result = try updates(self)
               if hasChanges {
                   try save()
               }
               return result
           }
       }
   }
   ```

2. **Efficient Queries with Projections**
   ```swift
   // Use lightweight projections for UI
   struct WalletSummary: Codable {
       let id: UUID
       let name: String
       let balance: UInt64
   }
   
   extension ModelContext {
       func fetchWalletSummaries() async -> [WalletSummary] {
           let descriptor = FetchDescriptor<HDWallet>(
               sortBy: [SortDescriptor(\.name)]
           )
           
           guard let wallets = try? fetch(descriptor) else { return [] }
           
           return wallets.map { wallet in
               WalletSummary(
                   id: wallet.id,
                   name: wallet.name,
                   balance: wallet.totalBalance
               )
           }
       }
   }
   ```

### Recommended Architecture: iOS-Native Patterns

```
┌─────────────────────────────────────────────────┐
│                    Views                        │
│      (SwiftUI with @Query / @ObservedObject)   │
└────────────────────┬────────────────────────────┘
                     │ Observes
                     ▼
┌─────────────────────────────────────────────────┐
│              View Models (Optional)             │
│         (Coordinate complex UI logic)           │
└────────────────────┬────────────────────────────┘
                     │ Uses
                     ▼
┌─────────────────────────────────────────────────┐
│                State Container                  │
│    (SwiftData + Minimal @Published state)      │
│         Chosen Architecture Pattern:            │
│         • TCA (Recommended)                     │
│         • MVVM + Combine                        │
│         • Actor-based                           │
│         • SwiftData-first                       │
└────────────────────┬────────────────────────────┘
                     │ Delegates to
                     ▼
┌─────────────────────────────────────────────────┐
│              Service Layer (Actors)             │
│         (Business logic, no state)              │
└────────────────────┬────────────────────────────┘
                     │ Uses
                     ▼
┌─────────────────────────────────────────────────┐
│           SDK Coordinator (Actor)               │
│      (Thread-safe FFI management)               │
└─────────────────────────────────────────────────┘
```

### iOS-Native Migration Strategy

1. **Phase 1: Incremental Consolidation**
   ```swift
   // Feature flags for gradual migration
   enum FeatureFlags {
       static let useNewStateManagement = true
       static let useTCA = false // Enable per feature
   }
   
   // Wrapper to support both patterns during migration
   @MainActor
   final class MigrationStateWrapper: ObservableObject {
       @Published var legacyState: AppState?
       @Published var newState: UnifiedState?
       
       var wallets: [HDWallet] {
           if FeatureFlags.useNewStateManagement {
               return newState?.wallets ?? []
           } else {
               return legacyState?.wallets ?? []
           }
       }
   }
   ```

2. **Phase 2: Feature-by-Feature Migration**
   - Week 1-2: Migrate wallet list to new pattern
   - Week 3-4: Migrate transaction history
   - Week 5-6: Migrate Platform features
   - Week 7: Remove legacy code

3. **Phase 3: Performance Optimization**
   - Implement proper background task scheduling
   - Add memory pressure handling
   - Optimize SwiftData queries
   - Implement proper caching strategies

### Key Benefits of iOS-Native Refactoring

1. **Single Source of Truth**: SwiftData becomes the authoritative data source
2. **Type Safety**: Leverage Swift's strong typing and actors for thread safety
3. **Better Testability**: Protocol-oriented design enables easy mocking
4. **Performance**: Native iOS patterns optimize for battery and memory
5. **Maintainability**: Familiar patterns for iOS developers
6. **Apple Ecosystem**: First-class integration with SwiftUI, Combine, and Swift Concurrency

### Comparison of Architecture Options

| Aspect | TCA | MVVM + Combine | Actor-Based | SwiftData-First |
|--------|-----|----------------|-------------|-----------------|
| Learning Curve | High | Medium | Low | Low |
| Testability | Excellent | Good | Good | Medium |
| Performance | Good | Good | Excellent | Excellent |
| SwiftUI Integration | Excellent | Good | Good | Native |
| Team Familiarity | Low | High | Medium | High |
| Debugging | Excellent | Good | Good | Medium |
| Flexibility | High | Medium | High | Low |

### Immediate Actions

1. **Audit Current State Dependencies**
   ```swift
   // Add temporary logging to understand data flow
   extension WalletService {
       func logStateChange(_ change: String, file: String = #file, line: Int = #line) {
           #if DEBUG
           print("🔍 State Change: \(change) at \(file):\(line)")
           #endif
       }
   }
   ```

2. **Implement Gradual Migration**
   ```swift
   // Start with a single feature behind feature flag
   struct WalletListView: View {
       @StateObject private var viewModel = FeatureFlags.useNewArchitecture 
           ? NewWalletViewModel() 
           : LegacyWalletViewModel()
   }
   ```

3. **Establish iOS Coding Standards**
   - Prefer actors for concurrent state management
   - Use `@Query` for SwiftData-backed views
   - Implement protocols for all services
   - Use `AsyncSequence` for event streams
   - Leverage `@Observable` macro (iOS 17+)

4. **Performance Monitoring**
   ```swift
   // Add metrics collection
   import os.signpost
   
   let signpostLog = OSLog(subsystem: "com.dash.wallet", category: "Performance")
   
   func measureStateUpdate<T>(_ operation: () async throws -> T) async rethrows -> T {
       let signpostID = OSSignpostID(log: signpostLog)
       os_signpost(.begin, log: signpostLog, name: "State Update", signpostID: signpostID)
       defer { os_signpost(.end, log: signpostLog, name: "State Update", signpostID: signpostID) }
       return try await operation()
   }
   ```

5. **Memory Pressure Handling**
   ```swift
   // Implement proper cleanup
   class AppDelegate: NSObject, UIApplicationDelegate {
       func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
           Task { @MainActor in
               // Clear caches
               ImageCache.shared.removeAll()
               // Trim SwiftData
               modelContext.autosaveEnabled = false
               try? modelContext.save()
               modelContext.reset()
           }
       }
   }
   ```

### Recommended Path Forward

1. **Choose TCA for new features** - Provides the most structure and best testing story
2. **Use MVVM + Combine for existing feature updates** - Familiar to most iOS developers
3. **Implement Actor-based coordinators** - For SDK and network management
4. **Keep SwiftData as source of truth** - But add proper abstractions on top

This iOS-native approach will create a more maintainable, performant, and idiomatic codebase that iOS developers will find familiar and easy to work with.