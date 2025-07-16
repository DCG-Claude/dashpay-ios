## SwiftData Threading Crashes Investigation Report

### Executive Summary

The DashPay iOS application is experiencing critical threading crashes due to improper SwiftData model access across different execution contexts. The crashes stem from SwiftData's complex threading model, lazy loading behavior, @Query property wrapper conflicts, and ModelContext container sharing issues. This report provides a comprehensive analysis of root causes and multiple solution approaches.

### Root Cause Analysis

#### 1. **SwiftData's Lazy Loading and Relationship Loading Issues**

SwiftData uses lazy loading for relationships, which can trigger crashes when:
- A model's relationships are accessed from a different context than where it was fetched
- Lazy-loaded properties are accessed after the original ModelContext is deallocated
- Cross-context relationship traversal occurs during SwiftUI view updates

**Example of Lazy Loading Crash**:
```swift
// ModelContext 1 (Main Thread)
let address = try modelContext.fetch(FetchDescriptor<HDWatchedAddress>()).first!

// ModelContext 2 (Background Thread)
Task {
    // CRASH: Lazy loads balance relationship from wrong context
    let balance = address.balance // <- Crash here
    print("Balance: \(balance?.totalBalance ?? 0)")
}
```

#### 2. **@Query Property Wrapper Conflicts**

The @Query property wrapper creates its own observation mechanism that can conflict with:
- Manual ModelContext operations
- Background updates to the same data
- Multiple @Query properties observing related data

**Example of @Query Observation Conflict**:
```swift
struct WalletView: View {
    @Query(sort: \HDWatchedAddress.address) 
    private var addresses: [HDWatchedAddress]
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List(addresses) { address in
            // View updates trigger re-fetches
            AddressRow(address: address)
                .task {
                    // CONFLICT: Background update while @Query is observing
                    await updateBalance(for: address)
                }
        }
    }
    
    func updateBalance(for address: HDWatchedAddress) async {
        // This can conflict with @Query's observation
        address.balance = await fetchBalance()
        try? modelContext.save() // <- Potential crash
    }
}
```

#### 3. **ModelContext Container Sharing Issues**

SwiftData's ModelContainer is designed to be shared, but ModelContext instances are not:
- Each actor/thread needs its own ModelContext
- Passing models between contexts requires special handling
- Container configuration must be consistent across contexts

**Example of Container Sharing Issue**:
```swift
// Incorrect: Sharing ModelContext
class DataManager {
    let modelContext: ModelContext // Shared across threads - WRONG!
    
    init(container: ModelContainer) {
        self.modelContext = container.mainContext
    }
}

// Correct: Each context gets its own ModelContext
actor DataActor {
    let modelContainer: ModelContainer
    var modelContext: ModelContext { 
        ModelContext(modelContainer) // New context per actor
    }
}
```

#### 4. **SwiftUI View Update Cycle Interactions**

SwiftUI's view update mechanism can trigger SwiftData operations at unexpected times:
- View body re-evaluations can access models mid-transaction
- @StateObject and @ObservedObject updates can cross thread boundaries
- Environment injection can create context mismatches

### Comprehensive Code Examples

#### 1. **Complete ModelActor Implementation**

```swift
// Proper ModelActor setup with ModelContainer
@ModelActor
actor WalletDataActor {
    // ModelActor provides modelContainer and modelContext automatically
    
    func updateAddressBalance(
        addressID: PersistentIdentifier, 
        newBalance: Int64
    ) async throws {
        // Fetch in actor's context
        guard let address = self[addressID, as: HDWatchedAddress.self] else {
            throw WalletError.addressNotFound
        }
        
        // Create or update balance in same context
        if let existingBalance = address.balance {
            existingBalance.totalBalance = newBalance
            existingBalance.confirmedBalance = newBalance
        } else {
            let balance = Balance()
            balance.totalBalance = newBalance
            balance.confirmedBalance = newBalance
            modelContext.insert(balance)
            address.balance = balance
        }
        
        try modelContext.save()
    }
    
    func fetchAllAddresses() async throws -> [AddressData] {
        let descriptor = FetchDescriptor<HDWatchedAddress>(
            sortBy: [SortDescriptor(\.address)]
        )
        let addresses = try modelContext.fetch(descriptor)
        
        // Convert to thread-safe data transfer objects
        return addresses.map { address in
            AddressData(
                id: address.persistentModelID,
                address: address.address,
                balance: address.balance?.totalBalance ?? 0
            )
        }
    }
}

// Thread-safe data transfer object
struct AddressData: Sendable {
    let id: PersistentIdentifier
    let address: String
    let balance: Int64
}
```

#### 2. **Background ModelContext Pattern**

```swift
// Alternative: Manual background context management
class WalletDataService {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    func performBackgroundUpdate() async throws {
        // Create new context for background work
        let backgroundContext = ModelContext(modelContainer)
        backgroundContext.autosaveEnabled = false // Manual save control
        
        try await backgroundContext.perform {
            let descriptor = FetchDescriptor<HDWatchedAddress>()
            let addresses = try backgroundContext.fetch(descriptor)
            
            for address in addresses {
                // Update in background context
                address.lastUpdated = Date()
            }
            
            // Single save at end of batch
            try backgroundContext.save()
        }
    }
}

// Extension for safe context execution
extension ModelContext {
    func perform<T>(_ block: @escaping () throws -> T) async rethrows -> T {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

#### 3. **Detached Models Pattern**

```swift
// Pattern for passing models between contexts
struct DetachedAddress: Codable, Sendable {
    let id: String
    let address: String
    let balance: Int64
    let isWatched: Bool
    
    init(from model: HDWatchedAddress) {
        self.id = model.id
        self.address = model.address
        self.balance = model.balance?.totalBalance ?? 0
        self.isWatched = model.isWatched
    }
}

class CrossContextService {
    @MainActor
    func detachAddress(_ address: HDWatchedAddress) -> DetachedAddress {
        DetachedAddress(from: address)
    }
    
    func attachAddress(
        _ detached: DetachedAddress, 
        to context: ModelContext
    ) throws -> HDWatchedAddress {
        let address = HDWatchedAddress()
        address.id = detached.id
        address.address = detached.address
        address.isWatched = detached.isWatched
        
        if detached.balance > 0 {
            let balance = Balance()
            balance.totalBalance = detached.balance
            context.insert(balance)
            address.balance = balance
        }
        
        context.insert(address)
        return address
    }
}
```

#### 4. **Serial Queue Pattern**

```swift
// Alternative: Serial queue for SwiftData operations
actor SerialDataQueue {
    private let modelContainer: ModelContainer
    private let queue = DispatchQueue(label: "com.dash.wallet.data", qos: .userInitiated)
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    func execute<T>(_ operation: @escaping (ModelContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let context = ModelContext(self.modelContainer)
                do {
                    let result = try operation(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// Usage
let dataQueue = SerialDataQueue(modelContainer: container)
let addresses = try await dataQueue.execute { context in
    try context.fetch(FetchDescriptor<HDWatchedAddress>())
}
```

#### 5. **Combine/AsyncSequence Pattern**

```swift
// Using AsyncSequence for reactive updates
class WalletDataStream {
    private let modelContainer: ModelContainer
    
    func addressUpdates() -> AsyncStream<[AddressUpdate]> {
        AsyncStream { continuation in
            let context = ModelContext(modelContainer)
            
            // Set up notification observer
            let observer = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: nil,
                queue: .main
            ) { notification in
                Task {
                    let updates = await self.processChanges(notification, in: context)
                    continuation.yield(updates)
                }
            }
            
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    private func processChanges(
        _ notification: Notification,
        in context: ModelContext
    ) async -> [AddressUpdate] {
        // Extract and transform changes safely
        []
    }
}

struct AddressUpdate: Sendable {
    let id: PersistentIdentifier
    let changeType: ChangeType
    let newBalance: Int64?
    
    enum ChangeType: Sendable {
        case inserted, updated, deleted
    }
}
```

### SwiftData-Specific Best Practices

#### 1. **Using fetchIdentifier() for Cross-Context Model Passing**

```swift
@MainActor
class WalletViewModel: ObservableObject {
    private let dataActor: WalletDataActor
    
    func updateAddress(_ address: HDWatchedAddress) async throws {
        // Get identifier for cross-context passing
        let identifier = address.persistentModelID
        
        // Pass identifier to actor, not the model
        try await dataActor.updateAddressBalance(
            addressID: identifier,
            newBalance: 1000
        )
    }
}
```

#### 2. **Autosave Management for Background Contexts**

```swift
func configureBatchContext() -> ModelContext {
    let context = ModelContext(modelContainer)
    
    // Disable autosave for batch operations
    context.autosaveEnabled = false
    
    // Configure undo manager
    context.undoManager = nil
    
    return context
}

func performBatchUpdate(using context: ModelContext) async throws {
    // Perform multiple operations
    for i in 0..<1000 {
        let address = HDWatchedAddress()
        address.address = "address_\(i)"
        context.insert(address)
        
        // Save periodically to manage memory
        if i % 100 == 0 {
            try context.save()
        }
    }
    
    // Final save
    try context.save()
}
```

#### 3. **Transaction Handling for Batch Operations**

```swift
extension ModelContext {
    func transaction<T>(_ block: () throws -> T) throws -> T {
        // Begin implicit transaction
        let hasChanges = self.hasChanges
        
        do {
            let result = try block()
            if self.hasChanges {
                try self.save()
            }
            return result
        } catch {
            // Rollback on error
            if !hasChanges {
                self.rollback()
            }
            throw error
        }
    }
}

// Usage
try modelContext.transaction {
    let address = HDWatchedAddress()
    modelContext.insert(address)
    
    let balance = Balance()
    modelContext.insert(balance)
    
    address.balance = balance
    // Automatically saved at end of transaction
}
```

#### 4. **@Query Handling with Background Updates**

```swift
// Safe pattern for @Query with background updates
struct WalletDashboard: View {
    @Query private var addresses: [HDWatchedAddress]
    @State private var isUpdating = false
    
    private let dataActor: WalletDataActor
    
    var body: some View {
        List(addresses) { address in
            AddressRow(address: address)
                .disabled(isUpdating)
        }
        .task {
            await updateInBackground()
        }
    }
    
    private func updateInBackground() async {
        isUpdating = true
        defer { isUpdating = false }
        
        // Don't directly modify @Query results
        // Use actor with identifiers instead
        for address in addresses {
            try? await dataActor.refreshBalance(
                for: address.persistentModelID
            )
        }
    }
}
```

### SwiftUI Integration Considerations

#### 1. **Handling @Query with ModelActor**

```swift
// ViewModel pattern for @Query + ModelActor
@MainActor
class AddressListViewModel: ObservableObject {
    @Published var addressData: [AddressData] = []
    private let dataActor: WalletDataActor
    
    init(dataActor: WalletDataActor) {
        self.dataActor = dataActor
    }
    
    func loadAddresses() async {
        do {
            // Fetch from actor, not @Query
            addressData = try await dataActor.fetchAllAddresses()
        } catch {
            print("Failed to load addresses: \(error)")
        }
    }
    
    func updateAddress(id: PersistentIdentifier, balance: Int64) async {
        try? await dataActor.updateAddressBalance(
            addressID: id,
            newBalance: balance
        )
        // Refresh after update
        await loadAddresses()
    }
}

struct AddressListView: View {
    @StateObject private var viewModel: AddressListViewModel
    
    init(dataActor: WalletDataActor) {
        _viewModel = StateObject(
            wrappedValue: AddressListViewModel(dataActor: dataActor)
        )
    }
    
    var body: some View {
        List(viewModel.addressData) { data in
            AddressDataRow(data: data) {
                Task {
                    await viewModel.updateAddress(
                        id: data.id,
                        balance: data.balance + 100
                    )
                }
            }
        }
        .task {
            await viewModel.loadAddresses()
        }
    }
}
```

#### 2. **@Environment(\.modelContext) Safe Usage**

```swift
struct SafeModelContextView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Button("Add Address") {
            // Safe: Synchronous operation in view context
            addAddress()
        }
        .task {
            // Unsafe: Don't use environment context in tasks
            // await doBackgroundWork(modelContext) // WRONG!
            
            // Safe: Use actor or create new context
            await doBackgroundWorkSafely()
        }
    }
    
    private func addAddress() {
        let address = HDWatchedAddress()
        modelContext.insert(address)
        try? modelContext.save()
    }
    
    private func doBackgroundWorkSafely() async {
        // Create actor or use dedicated service
        let dataActor = WalletDataActor(
            modelContainer: modelContext.container
        )
        try? await dataActor.performBackgroundWork()
    }
}
```

#### 3. **SwiftUI Preview Handling**

```swift
// Preview-safe SwiftData configuration
struct PreviewHelper {
    static let previewContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: HDWatchedAddress.self, Balance.self,
            configurations: config
        )
        
        // Add sample data in main context
        let context = container.mainContext
        
        let address = HDWatchedAddress()
        address.address = "Preview Address"
        context.insert(address)
        
        let balance = Balance()
        balance.totalBalance = 1000
        context.insert(balance)
        address.balance = balance
        
        try? context.save()
        
        return container
    }()
    
    static let previewDataActor = WalletDataActor(
        modelContainer: previewContainer
    )
}

#Preview {
    AddressListView(dataActor: PreviewHelper.previewDataActor)
        .modelContainer(PreviewHelper.previewContainer)
}
```

### Production Considerations

#### 1. **Debugging Strategies**

```swift
// Debug wrapper for SwiftData operations
class DebugModelContext {
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.dash.wallet", category: "SwiftData")
    
    init(_ context: ModelContext) {
        self.context = context
    }
    
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        let threadName = Thread.current.name ?? "Unknown"
        logger.debug("Fetching \(T.self) on thread: \(threadName)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try context.fetch(descriptor)
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        logger.debug("Fetched \(results.count) items in \(duration)s")
        return results
    }
    
    func save() throws {
        let changes = context.insertedModelsArray.count + 
                     context.deletedModelsArray.count
        logger.debug("Saving \(changes) changes")
        
        do {
            try context.save()
            logger.debug("Save successful")
        } catch {
            logger.error("Save failed: \(error)")
            throw error
        }
    }
}

// Thread safety assertions
extension ModelContext {
    func assertMainThread() {
        assert(Thread.isMainThread, "ModelContext accessed off main thread")
    }
    
    func assertBackgroundThread() {
        assert(!Thread.isMainThread, "Background operation on main thread")
    }
}
```

#### 2. **Performance Implications**

```swift
// Performance monitoring for different approaches
class PerformanceMonitor {
    enum ApproachType {
        case modelActor
        case backgroundContext
        case serialQueue
        case detachedModels
    }
    
    func measure<T>(
        approach: ApproachType,
        operation: () async throws -> T
    ) async throws -> (result: T, metrics: Metrics) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        
        let result = try await operation()
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let memoryDelta = getMemoryUsage() - startMemory
        
        let metrics = Metrics(
            approach: approach,
            duration: duration,
            memoryDelta: memoryDelta,
            threadCount: Thread.allThreads.count
        )
        
        logMetrics(metrics)
        return (result, metrics)
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

struct Metrics {
    let approach: PerformanceMonitor.ApproachType
    let duration: TimeInterval
    let memoryDelta: Int64
    let threadCount: Int
}
```

#### 3. **Gradual Rollout with Feature Flags**

```swift
// Feature flag system for gradual migration
struct FeatureFlags {
    static var useModelActor: Bool {
        UserDefaults.standard.bool(forKey: "feature.useModelActor")
    }
    
    static var useDetachedModels: Bool {
        UserDefaults.standard.bool(forKey: "feature.useDetachedModels")
    }
    
    static var enableThreadingAssertions: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "feature.threadingAssertions")
        #endif
    }
}

// Gradual migration wrapper
class DataService {
    private let modelContainer: ModelContainer
    private let modelActor: WalletDataActor?
    private let legacyService: LegacyDataService?
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        
        if FeatureFlags.useModelActor {
            self.modelActor = WalletDataActor(modelContainer: modelContainer)
            self.legacyService = nil
        } else {
            self.modelActor = nil
            self.legacyService = LegacyDataService(modelContainer: modelContainer)
        }
    }
    
    func fetchAddresses() async throws -> [AddressData] {
        if let modelActor = modelActor {
            return try await modelActor.fetchAllAddresses()
        } else if let legacyService = legacyService {
            return try await legacyService.fetchAddresses()
        } else {
            throw DataServiceError.noImplementation
        }
    }
}

// A/B testing for performance comparison
class ABTestingService {
    func compareApproaches() async {
        let testData = generateTestData()
        
        // Test ModelActor approach
        let actorMetrics = try? await measureApproach(.modelActor) {
            // Implementation
        }
        
        // Test Background Context approach
        let contextMetrics = try? await measureApproach(.backgroundContext) {
            // Implementation
        }
        
        // Log results for analysis
        Analytics.log(event: "threading_approach_comparison", parameters: [
            "modelActor_duration": actorMetrics?.duration ?? -1,
            "backgroundContext_duration": contextMetrics?.duration ?? -1
        ])
    }
}
```

### Migration Strategy

#### Phase 1: Immediate Stabilization (Day 1)
1. Add thread assertions to catch violations in debug
2. Fix critical crashes in WalletService with temporary @MainActor wrappers
3. Disable autosave on problematic contexts
4. Add comprehensive crash logging

#### Phase 2: ModelActor Implementation (Days 2-3)
1. Create WalletDataActor for all wallet operations
2. Create PlatformDataActor for identity/document operations
3. Update ViewModels to use actors instead of direct context access
4. Implement performance monitoring

#### Phase 3: Detached Model Pattern (Days 4-5)
1. Create Codable versions of all SwiftData models
2. Implement conversion utilities
3. Update cross-layer bridges to use detached models
4. Add unit tests for model conversions

#### Phase 4: UI Layer Refactoring (Days 6-7)
1. Replace @Query with ViewModel-based approach where needed
2. Update all Task blocks to use proper isolation
3. Implement preview-safe configurations
4. Add UI tests for concurrent operations

#### Phase 5: Production Rollout (Week 2)
1. Enable feature flags for 10% of users
2. Monitor crash rates and performance metrics
3. Gradually increase rollout percentage
4. Full rollout after stability confirmation

### Testing Strategy

```swift
// Comprehensive test suite for threading safety
class SwiftDataThreadingTests: XCTestCase {
    
    func testConcurrentModelAccess() async throws {
        let container = createTestContainer()
        let actor = WalletDataActor(modelContainer: container)
        
        // Spawn multiple concurrent operations
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    try await actor.createAddress(index: i)
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify all addresses created
        let addresses = try await actor.fetchAllAddresses()
        XCTAssertEqual(addresses.count, 100)
    }
    
    func testCrossContextModelPassing() async throws {
        let container = createTestContainer()
        let mainContext = container.mainContext
        let actor = WalletDataActor(modelContainer: container)
        
        // Create in main context
        let address = HDWatchedAddress()
        address.address = "test_address"
        mainContext.insert(address)
        try mainContext.save()
        
        let identifier = address.persistentModelID
        
        // Update in actor context
        try await actor.updateAddressBalance(
            addressID: identifier,
            newBalance: 1000
        )
        
        // Verify in main context
        mainContext.refreshAllObjects()
        XCTAssertEqual(address.balance?.totalBalance, 1000)
    }
    
    func testRaceConditionPrevention() async throws {
        let container = createTestContainer()
        let actor = WalletDataActor(modelContainer: container)
        
        // Create address
        let addressID = try await actor.createAddressAndReturnID()
        
        // Attempt concurrent modifications
        async let update1 = actor.updateAddressBalance(addressID: addressID, newBalance: 100)
        async let update2 = actor.updateAddressBalance(addressID: addressID, newBalance: 200)
        async let update3 = actor.updateAddressBalance(addressID: addressID, newBalance: 300)
        
        // All should complete without crashes
        _ = try await (update1, update2, update3)
        
        // Final state should be deterministic (last write wins)
        let finalBalance = try await actor.getBalance(for: addressID)
        XCTAssertTrue([100, 200, 300].contains(finalBalance))
    }
}
```

### Conclusion

SwiftData's threading model requires careful consideration of multiple factors beyond simple actor isolation. The combination of lazy loading, @Query observation, ModelContext boundaries, and SwiftUI integration creates a complex environment where crashes can occur from multiple sources. This comprehensive analysis provides multiple solution patterns, allowing teams to choose the approach that best fits their architecture while maintaining thread safety and performance. The key is understanding that SwiftData is not just about data persistence—it's about managing a complex graph of objects across multiple execution contexts in a reactive UI framework.