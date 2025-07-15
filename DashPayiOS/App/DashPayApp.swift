import SwiftUI
import SwiftData
import UserNotifications
import SwiftDashSDK
import SwiftDashCoreSDK


@main
struct DashPayApp: App {
    @StateObject private var unifiedState = UnifiedAppState()
    @State private var shouldResetApp = false
    @State private var ffiInitializationFailed = false
    @State private var ffiInitializationError: Error?
    // private let notificationDelegate = NotificationDelegate()
    // private let consoleRedirect = ConsoleRedirect()
    
    init() {
        // Initialize unified FFI library early
        do {
            try UnifiedFFIInitializer.shared.initialize()
        } catch {
            print("🔴 Failed to initialize unified FFI library: \(error)")
            // Set state for user-visible error handling
            DispatchQueue.main.async {
                self.ffiInitializationFailed = true
                self.ffiInitializationError = error
            }
        }
        
        // Set up notification delegate
        // UNUserNotificationCenter.current().delegate = notificationDelegate
        
        // Start console redirection for debugging
        // consoleRedirect.start()  // DISABLED: Logs now appear in Xcode console
        
        // Note: Notification observer will be set up later to avoid self capture issues
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if ffiInitializationFailed {
                    // Show error view when FFI initialization fails
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("Initialization Failed")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Failed to initialize the wallet core library. The app cannot start without this critical component.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        if let error = ffiInitializationError {
                            Text("Error: \(error.localizedDescription)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button("Restart App") {
                            exit(0)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else if shouldResetApp {
                    // Show a simple loading view while resetting
                    VStack(spacing: 20) {
                        ProgressView("Resetting app...")
                            .scaleEffect(1.5)
                        Text("The app is being reset to its initial state.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // Reset the app state after a short delay
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                            await resetAppState()
                        }
                    }
                } else {
                    ContentView()
                        .environmentObject(unifiedState)
                        .environmentObject(unifiedState.walletService)
                        .environmentObject(unifiedState.platformState)
                        .environmentObject(unifiedState.unifiedState)
                        .environment(\.modelContext, unifiedState.modelContainer.mainContext)
                        .onReceive(NotificationCenter.default.publisher(for: .appShouldReset)) { _ in
                            shouldResetApp = true
                        }
                        .task {
                            // Initialize notification service
                            // _ = LocalNotificationService.shared
                            
                            // Add a small delay to ensure UI is ready
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                            print("🚀 ContentView task starting initialization...")
                            await unifiedState.initialize()
                        }
                }
            }
        }
    }
    
    @MainActor
    private func resetAppState() async {
        // Reset the unified state to initial state
        await unifiedState.reset()
        
        // Reinitialize the app state
        await unifiedState.initialize()
        
        // Reset the flag to show normal app content
        shouldResetApp = false
    }
}

@MainActor
class UnifiedAppState: ObservableObject {
    @Published var isInitialized = false
    @Published var error: Error?
    
    // Services from Core example
    let walletService: WalletService
    
    // State from Platform example
    let platformState: AppState
    
    // New unified state
    let unifiedState: UnifiedStateManager
    
    // SwiftData container
    let modelContainer: ModelContainer
    
    // SDKs
    private var coreSDK: DashSDK?
    private var platformWrapper: PlatformSDKWrapper?
    
    init() {
        print("🚀 UnifiedAppState.init() - Creating app state")
        
        // Initialize SwiftData using ModelContainerHelper
        do {
            modelContainer = try ModelContainerHelper.createContainer()
            print("✅ ModelContainer created successfully using ModelContainerHelper")
        } catch {
            print("🔴 Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
        
        // Initialize services
        self.walletService = WalletService.shared
        self.walletService.configure(modelContext: modelContainer.mainContext)
        print("✅ WalletService configured")
        
        // Ensure default peer configuration on first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.set(false, forKey: "useLocalPeers") // Default to public peers
            print("✅ First launch detected - defaulting to public peers")
        }
        
        self.platformState = AppState()
        print("✅ Platform AppState created")
        
        // Initialize with placeholder SDK that will be replaced during async initialization
        let stubSDK = DashSDKStub()
        // Platform wrapper requires real initialization, so we'll create it during async init
        self.unifiedState = UnifiedStateManager(
            coreSDK: stubSDK,
            platformWrapper: nil  // Will be set during initialization
        )
        print("✅ UnifiedStateManager created with stub SDK")
        
        // Configure FFI after all properties are initialized
        configureFFI()
        
        print("🔄 UnifiedAppState.init() completed - isInitialized: \(isInitialized)")
    }
    
    private func configureFFI() {
        print("🔧 Configuring FFI for real Core chain sync...")
        
        // FFI initialization is now handled internally by the SDK
        print("📝 FFI will be initialized when DashSDK is created")
    }
    
    func initialize() async {
        print("🚀 Starting UnifiedAppState initialization...")
        // Thread debugging removed - not available in async context
        
        
        // Remove SDK creation from here - let WalletService handle it
        // This matches the example app pattern where SDK is created on demand
        print("🔧 SDK will be created by WalletService when needed")
        
        // Initialize Platform AppState
        print("🔧 Initializing Platform AppState...")
        await MainActor.run {
            platformState.initializeSDK(modelContext: modelContainer.mainContext, existingCoreSDK: nil)
        }
        print("✅ Platform AppState initialized")
        
        // Wait a moment for Platform SDK initialization
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        if let platformWrapper = platformState.platformSDK {
            self.platformWrapper = platformWrapper
            print("✅ Got Platform SDK wrapper from Platform AppState")
            await unifiedState.updatePlatformWrapper(platformWrapper)
        } else {
            print("⚠️ Platform SDK not available - continuing with Core SDK only")
            // Platform SDK is optional for Core wallet testing
        }
        
        // SDK will be created on demand by WalletService
        print("✅ App initialization complete - SDK will be created when wallet connects")
        
        // Start auto-sync after initialization
        Task {
            print("🚀 Starting auto-sync task...")
            
            // Network monitor removed during simplification
            // walletService.networkMonitor = NetworkMonitor()
            print("✅ Connection simplified - network monitor removed")
            
            // Add a delay to ensure SwiftData has loaded wallets
            print("⏳ Waiting for SwiftData to load wallets...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // INTENTIONALLY DISABLED: Auto-sync and periodic sync features
            // 
            // Auto-sync and periodic sync are disabled to provide manual sync control.
            // This behavioral change allows developers and users to explicitly control when 
            // synchronization occurs, which is useful for:
            // - Testing specific sync scenarios without interference
            // - Debugging sync-related issues in a controlled environment
            // - Avoiding background sync interference during development
            // - Giving users explicit control over network usage and battery consumption
            // - Preventing unexpected sync operations during testing
            //
            // RATIONALE: Manual sync control provides better predictability and control
            // for both development and production use cases. Users can initiate sync
            // operations when desired through the UI.
            //
            // To re-enable automatic sync, uncomment the code blocks below:
            
            // Auto-sync (starts sync automatically after initialization)
            // print("🔄 Calling startAutoSync()...")
            // await walletService.startAutoSync()
            // print("✅ startAutoSync() completed")
            
            // Periodic sync (sets up recurring background sync)
            // walletService.setupPeriodicSync()
            // print("✅ Periodic sync setup completed")
            
            // Monitor app lifecycle
            setupLifecycleObservers()
            print("✅ Lifecycle observers setup completed")
        }
            
        isInitialized = true
        print("🎉 UnifiedAppState initialization completed successfully!")
    }
    
    func reset() async {
        // Reset published properties
        isInitialized = false
        error = nil
        
        // Disconnect and reset wallet service
        await walletService.disconnect()
        
        // Reset platform state properties
        platformState.sdk = nil
        platformState.coreSDK = nil
        platformState.platformSDK = nil
        platformState.assetLockBridge = nil
        platformState.isLoading = false
        platformState.showError = false
        platformState.errorMessage = ""
        platformState.showSuccess = false
        platformState.successMessage = ""
        platformState.identities = []
        platformState.contracts = []
        platformState.tokens = []
        platformState.documents = []
        
        // Reset unified state
        // unifiedState.isInitialized = false  // Read-only property - will be reset during reinitialization
        
        print("🔄 UnifiedAppState reset completed")
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        Task {
            // INTENTIONALLY DISABLED: Auto-sync on app foreground
            // 
            // Auto-sync is disabled to provide manual sync control when the app returns to foreground.
            // This behavioral change prevents automatic network activity and gives users explicit 
            // control over when sync occurs. This is particularly important for:
            // - Battery conservation by avoiding unnecessary background sync
            // - Network usage control in metered connection scenarios
            // - Predictable testing behavior without surprise sync operations
            // - User privacy by not automatically connecting to network on app resume
            //
            // RATIONALE: Manual sync control allows users to choose when to sync, providing
            // better control over their device resources and network usage.
            //
            // To re-enable automatic sync on app foreground, uncomment the line below:
            // await walletService.startAutoSync()
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Stop periodic sync when app goes to background
        walletService.stopPeriodicSync()
    }
}

// MARK: - Temporary Stubs

class DashSDKStub: DashSDKProtocol {
    func createTransaction(to: String, amount: UInt64, isAssetLock: Bool) async throws -> SwiftDashCoreSDK.Transaction {
        throw AssetLockError.assetLockGenerationFailed
    }
    
    func createAssetLockTransaction(amount: UInt64) async throws -> SwiftDashCoreSDK.Transaction {
        throw AssetLockError.assetLockGenerationFailed
    }
    
    func broadcastTransaction(_ tx: SwiftDashCoreSDK.Transaction) async throws -> String {
        throw AssetLockError.assetLockGenerationFailed
    }
    
    func getInstantLock(for txid: String) async throws -> InstantLock? {
        return nil
    }
    
    func waitForInstantLockResult(txid: String, timeout: TimeInterval) async throws -> InstantLock {
        throw AssetLockError.instantLockTimeout
    }
}

