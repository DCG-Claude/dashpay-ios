import Foundation
import SwiftData
import SwiftDashSDK
import SwiftDashCoreSDK
import Combine

// Extension for PlatformNetwork conversion
extension PlatformNetwork {
    func toDashNetwork() -> DashNetwork {
        switch self {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }
}

// SDK type placeholders
// Simple SDK wrapper for TokenService
public struct SimpleSDK {
    let handle: OpaquePointer?
    
    init(handle: OpaquePointer?) {
        self.handle = handle
    }
}

// Simple Identity type for SDK responses
public struct SDKIdentity {
    public let id: Data
    public let balance: UInt64
    public let publicKeys: [Any]
    
    public init(id: Data, balance: UInt64, publicKeys: [Any] = []) {
        self.id = id
        self.balance = balance
        self.publicKeys = publicKeys
    }
}

public struct SDK {
    public let identities = IdentitiesAPI()
    
    public init() {}
    
    public init(network: DashSDKNetwork) throws {
        // Mock initialization with network
        self.init()
        
        // Convert DashSDKNetwork to DashNetwork and store it
        let dashNetwork: DashNetwork
        switch network.rawValue {
        case 0: dashNetwork = .mainnet
        case 1: dashNetwork = .testnet
        case 3: dashNetwork = .devnet
        default: dashNetwork = .testnet
        }
        var mutableSelf = self
        mutableSelf.setNetwork(dashNetwork)
    }
    
    public static func initialize() {
        // Mock SDK initialization
    }
}

public struct IdentitiesAPI {
    public func fetchBalances(ids: [Data]) throws -> [Data: UInt64] {
        // TODO: DEVELOPMENT STUB - Replace with real Platform SDK integration
        // This method currently returns mock data for development purposes only.
        // When Platform SDK integration is complete, this should call:
        // - dash_sdk_get_identity_balance() or equivalent FFI function
        // - Handle proper error cases and network timeouts
        // - Return actual blockchain balances instead of random values
        print("⚠️ fetchBalances: Using mock data - replace with Platform SDK integration")
        return ids.reduce(into: [:]) { result, id in
            result[id] = UInt64.random(in: 0...1000000)
        }
    }
    
    public func get(id: String) throws -> SDKIdentity? {
        // TODO: DEVELOPMENT STUB - Replace with real Platform SDK integration
        // This method currently returns mock data for development purposes only.
        // When Platform SDK integration is complete, this should call:
        // - dash_sdk_get_identity() or equivalent FFI function
        // - Fetch real identity data from the blockchain
        // - Handle identity not found cases properly
        print("⚠️ get(id:): Using mock data - replace with Platform SDK integration")
        
        guard let idData = Data(hexString: id) ?? Data.identifier(fromBase58: id),
              idData.count == 32 else {
            throw SDKError.invalidParameter("Invalid identity ID format")
        }
        
        // Return a mock identity - THIS IS NOT REAL DATA
        return SDKIdentity(
            id: idData,
            balance: UInt64.random(in: 0...1000000),
            publicKeys: []
        )
    }
}

// SDK Error type
public enum SDKError: Error {
    case invalidData
    case networkError
    case unknown
    case invalidParameter(String)
    case invalidState(String)
    case serializationError(String)
    case protocolError(String)
    case cryptoError(String)
    case identityNotFound(String)
    case insufficientBalance(required: UInt64, available: UInt64)
    case documentAlreadyExists(String)
    case contractNotFound(String)
    case generalError(String)
}

@MainActor
class AppState: ObservableObject {
    @Published var sdk: SDK?
    @Published var coreSDK: DashSDK?
    @Published var platformSDK: PlatformSDKWrapper?
    @Published var assetLockBridge: AssetLockBridge?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false
    @Published var successMessage = ""
    
    @Published var identities: [IdentityModel] = []
    @Published var contracts: [ContractModel] = []
    @Published var tokens: [TokenModel] = []
    @Published var documents: [DocumentModel] = []
    
    @Published var currentNetwork: PlatformNetwork {
        didSet {
            UserDefaults.standard.set(currentNetwork.rawValue, forKey: "currentNetwork")
            Task {
                await switchNetwork(to: currentNetwork)
            }
        }
    }
    
    @Published var dataStatistics: (identities: Int, documents: Int, contracts: Int, tokenBalances: Int)?
    
    private let keychainSigner = KeychainSigner()
    private var _dataManager: DataManager?
    private var modelContext: ModelContext?
    
    var dataManager: DataManager? {
        return _dataManager
    }
    
    // Token system integration
    @Published var tokenService: TokenService?
    @Published var platformSigner: PlatformSigner?
    
    // Identity service integration
    @Published var identityService: IdentityService?
    
    // Document system integration
    @Published var documentService: DocumentService?
    
    // Combine subscriptions for sync events
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Load saved network preference or use default
        if let savedNetwork = UserDefaults.standard.string(forKey: "currentNetwork"),
           let network = PlatformNetwork(rawValue: savedNetwork) {
            self.currentNetwork = network
        } else {
            self.currentNetwork = .testnet
        }
    }
    
    func initializeSDK(modelContext: ModelContext, existingCoreSDK: DashSDK? = nil) {
        print("📍 AppState.initializeSDK() called")
        print("📍 Current thread in initializeSDK: \(Thread.current)")
        print("📍 Is main thread: \(Thread.isMainThread)")
        print("📍 Existing Core SDK provided: \(existingCoreSDK != nil)")
        
        // Save the model context for later use
        self.modelContext = modelContext
        
        // Initialize DataManager
        self._dataManager = DataManager(modelContext: modelContext, currentNetwork: currentNetwork)
        print("✅ DataManager initialized")
        
        Task { @MainActor in
            do {
                print("📍 Inside Task block")
                isLoading = true
                print("🔄 Initializing Dash SDK components... isLoading set to true")
                
                // Step 1: Use existing Core SDK if provided, otherwise create new one
                if let existingSDK = existingCoreSDK {
                    print("🔧 Using existing Core SDK instance...")
                    coreSDK = existingSDK
                    print("✅ Core SDK reused from UnifiedAppState")
                } else {
                    print("🔧 Initializing Core SDK...")
                    let dashNetwork = currentNetwork.toDashNetwork()
                    // Use centralized configuration manager
                    let coreConfig = try SPVConfigurationManager.shared.configuration(for: dashNetwork)
                    print("📍 SPV config obtained from manager")
                    
                    // Initialize Core SDK with configuration
                    print("🔧 Creating Core SDK instance...")
                    do {
                        let coreSdk = try DashSDK(configuration: coreConfig)
                        print("📍 DashSDK instance created")
                        coreSDK = coreSdk
                        print("✅ Core SDK initialized successfully")
                    } catch {
                        print("🔴 Core SDK initialization failed: \(error)")
                        
                        // Enhanced error diagnostics
                        if let sdkError = error as? SwiftDashCoreSDK.DashSDKError {
                            print("🔴 SDK Error type: \(sdkError)")
                            print("🔴 Recovery suggestion: \(sdkError.recoverySuggestion ?? "None")")
                        }
                        
                        // Log more context about the failure
                        print("🔴 Additional context:")
                        print("   - Network: \(currentNetwork.displayName)")
                        print("   - Platform SDK Network: \(currentNetwork.sdkNetwork)")
                        print("   - Raw Value: \(currentNetwork.rawValue)")
                        
                        throw error
                    }
                }
                
                // Step 1.5: SDK is now ready but not connected
                // Connection and sync will happen when WalletService connects a wallet
                print("✅ Core SDK ready (not connected yet - will connect when wallet is selected)")
                
                // Step 2: Initialize Platform SDK with Core context
                print("🔧 Initializing Platform SDK with Core integration...")
                do {
                    let platformSdk = try await initializePlatformSDK(with: coreSDK!)
                    platformSDK = platformSdk
                    print("✅ Platform SDK initialized successfully")
                    
                    // Test Platform SDK connection
                    print("🔍 Testing Platform SDK connection...")
                    // TODO: Implement proper Platform SDK connection test when available
                    // let isConnected = await platformSdk.testConnection()
                    // if isConnected {
                    //     print("✅ Platform SDK connection test passed")
                    //     
                    //     // Get network status
                    //     let networkStatus = await platformSdk.getNetworkStatus()
                    //     print("📊 Platform Network Status: \(networkStatus.statusDescription)")
                    //     print("📊 Response Time: \(networkStatus.formattedResponseTime)")
                    // } else {
                    //     print("🔴 Platform SDK connection test failed")
                    // }
                    print("⚠️ Platform SDK connection test skipped - not implemented yet")
                } catch {
                    print("🔴 Platform SDK initialization failed: \(error)")
                    
                    // Create a mock wrapper for compatibility but log the issue
                    print("⚠️ Falling back to limited Platform functionality")
                    platformSDK = nil
                }
                
                // Step 3: Create AssetLockBridge to connect Core and Platform
                if let platformSdk = platformSDK {
                    print("🔧 Creating AssetLockBridge for Core-Platform integration...")
                    assetLockBridge = await AssetLockBridge(coreSDK: coreSDK!, platformSDK: platformSdk, walletService: WalletService.shared)
                    print("✅ AssetLockBridge created successfully")
                } else {
                    print("⚠️ AssetLockBridge creation skipped - Platform SDK not available")
                    assetLockBridge = nil
                }
                
                // Step 4: Initialize mock SDK for backward compatibility
                SDK.initialize()
                sdk = SDK()
                
                // Step 5: Initialize TokenService, PlatformSigner, and IdentityService
                print("🪙 Initializing Token Service...")
                let signer = PlatformSigner()
                platformSigner = signer
                let tokenSvc = TokenService()
                tokenService = tokenSvc
                print("✅ Token Service initialized")
                
                print("👤 Initializing Identity Service...")
                let identitySvc = IdentityService(dataManager: _dataManager!, platformSDK: platformSDK)
                identityService = identitySvc
                print("✅ Identity Service initialized")
                
                // Step 6: Initialize DocumentService
                print("📄 Initializing Document Service...")
                if let platformSdk = platformSDK {
                    let docService = DocumentService(platformSDK: platformSdk, dataManager: _dataManager!)
                    documentService = docService
                    print("✅ Document Service initialized")
                } else {
                    print("⚠️ Document Service initialization skipped - Platform SDK not available")
                }
                
                // Step 7: Load persisted data
                print("📂 Loading persisted data...")
                await loadPersistedData()
                
                isLoading = false
                print("🎉 SDK initialization complete!")
                
            } catch {
                print("🔴 SDK initialization failed: \(error)")
                print("🔴 Error type: \(type(of: error))")
                print("🔴 Error details: \(error)")
                if let nsError = error as NSError? {
                    print("🔴 NSError domain: \(nsError.domain)")
                    print("🔴 NSError code: \(nsError.code)")
                    print("🔴 NSError userInfo: \(nsError.userInfo)")
                }
                showError(message: "Failed to initialize SDK: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }
    
    
    // SDK connection and sync is now handled by WalletService when a wallet is connected
    // private func startBlockchainSync(sdk: DashSDK) async throws {
    //     // Removed - sync happens in WalletService.connect()
    // }
    
    private func handleSyncEvent(_ event: SPVEvent) async {
        switch event {
        case .connectionStatusChanged(let connected):
            print("🌐 Connection status: \(connected ? "Connected" : "Disconnected")")
            
        case .syncProgressUpdated(let progress):
            print("📊 Sync: \(progress.progress * 100)% - \(progress.currentHeight)/\(progress.totalHeight) headers")
            
        case .transactionReceived(let txid, let confirmed, let amount, let addresses, let height):
            print("💰 Transaction received: \(amount) DASH to \(addresses.joined(separator: ", "))")
            print("   TXID: \(txid)")
            print("   Confirmed: \(confirmed)")
            if let height = height {
                print("   Block: \(height)")
            }
            
        case .balanceUpdated(let balance):
            print("💎 Balance updated: \(balance.total) DASH")
            
        case .error(let error):
            print("🔴 SPV Error: \(error)")
            showError(message: "Sync error: \(error)")
            
        default:
            print("📡 SPV Event: \(event)")
        }
    }
    
    private func initializePlatformSDK(with coreSDK: DashSDK) async throws -> PlatformSDKWrapper {
        print("🌐 Setting up Platform SDK with network: \(currentNetwork)")
        
        // Create Platform SDK wrapper with Core SDK integration
        let platformSDK = try await PlatformSDKWrapper(network: currentNetwork, coreSDK: coreSDK)
        
        return platformSDK
    }
    
    func loadPersistedData() async {
        guard let dataManager = _dataManager else { return }
        
        do {
            // Load identities
            identities = try dataManager.fetchIdentities()
            
            // Load contracts
            contracts = try dataManager.fetchContracts()
            
            // Load documents for all contracts
            var allDocuments: [DocumentModel] = []
            for contract in contracts {
                let docs = try dataManager.fetchDocuments(contractId: contract.id)
                allDocuments.append(contentsOf: docs)
            }
            documents = allDocuments
            
            // Load token data for identities - first from persistence, then refresh from network
            await loadPersistedTokens()
            await loadTokensForIdentities()
        } catch {
            print("Error loading persisted data: \(error)")
        }
    }
    
    // MARK: - Token Management Methods
    
    /// Discover available token IDs from various sources
    private func discoverAvailableTokenIds() async -> [String] {
        // Priority order: configuration file > blockchain registry > fallback list
        
        // 1. Try to load from configuration file
        if let configTokenIds = loadTokenIdsFromConfiguration() {
            print("📄 Loaded \(configTokenIds.count) token IDs from configuration")
            return configTokenIds
        }
        
        // 2. Try to discover from blockchain/registry (when available)
        if let discoveredTokenIds = await discoverTokenIdsFromBlockchain() {
            print("🔍 Discovered \(discoveredTokenIds.count) token IDs from blockchain")
            return discoveredTokenIds
        }
        
        // 3. Fall back to a curated list of known tokens
        let fallbackTokenIds = getFallbackTokenIds()
        print("⚠️ Using fallback token IDs list with \(fallbackTokenIds.count) tokens")
        return fallbackTokenIds
    }
    
    /// Load token IDs from a local configuration file
    private func loadTokenIdsFromConfiguration() -> [String]? {
        // Try to load from Bundle resources
        guard let url = Bundle.main.url(forResource: "tokens", withExtension: "json") else {
            print("📄 No tokens.json configuration file found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let tokenDict = json as? [String: Any],
               let networkTokens = tokenDict[currentNetwork.rawValue] as? [String: Any],
               let tokenIds = networkTokens["tokenIds"] as? [String] {
                return tokenIds
            }
        } catch {
            print("📄 Failed to parse tokens configuration: \(error)")
        }
        
        return nil
    }
    
    /// Discover token IDs from blockchain registry or configuration file
    private func discoverTokenIdsFromBlockchain() async -> [String]? {
        // TODO: Implement blockchain token discovery when Platform SDK supports it
        // For now, load token IDs from configuration file instead of returning nil
        return loadTokenIdsFromConfiguration()
        
        /*
        // Future implementation when Platform SDK is ready:
        guard let platformSdk = platformSDK else { 
            return loadTokenIdsFromConfiguration() 
        }
        
        do {
            let sdkHandle = await platformSdk.sdkHandle
            let sdk = SimpleSDK(handle: sdkHandle)
            
            // Use a hypothetical token registry query
            let discoveredTokens = try await tokenService?.discoverTokens(sdk: sdk, network: currentNetwork)
            return discoveredTokens?.map { $0.id } ?? loadTokenIdsFromConfiguration()
        } catch {
            print("🔍 Failed to discover tokens from blockchain: \(error)")
            return loadTokenIdsFromConfiguration()
        }
        */
    }
    
    /// Load token IDs from configuration file
    private func loadTokenIdsFromConfiguration() -> [String]? {
        guard let path = Bundle.main.path(forResource: "tokens", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("🔍 Failed to load tokens.json configuration file")
            return nil
        }
        
        let networkKey = currentNetwork.rawValue
        guard let networkTokens = json[networkKey] as? [String: Any],
              let tokenIds = networkTokens["tokenIds"] as? [String] else {
            print("🔍 No token IDs found for network: \(networkKey)")
            return nil
        }
        
        print("🔍 Loaded \(tokenIds.count) token IDs from configuration for network: \(networkKey)")
        return tokenIds
    }
    
    /// Get fallback token IDs for the current network
    private func getFallbackTokenIds() -> [String] {
        // Return network-specific fallback token IDs as a last resort
        // NOTE: These are placeholder/example token IDs - replace with real token IDs when available
        switch currentNetwork {
        case .testnet:
            return [
                "AEzd9k8r8P3u8RGU5tGz8kXR9V5hN2J7K3M4P6Q8S1T2", // Testnet placeholder token
                "BF2e9l9s9Q4v9SGV6uH9l9YS0W6iO3K8L4N5Q7R9T2U3"  // Another testnet placeholder
            ]
        case .mainnet:
            return [
                "C3f4g5h6i7j8k9l0m1n2o3p4q5r6s7t8u9v0w1x2y3z4", // Mainnet placeholder token
                "D4g5h6i7j8k9l0m1n2o3p4q5r6s7t8u9v0w1x2y3z4a5"  // Another mainnet placeholder
            ]
        case .devnet:
            return [
                "E5h6i7j8k9l0m1n2o3p4q5r6s7t8u9v0w1x2y3z4a5b6", // Devnet placeholder token
                "F6i7j8k9l0m1n2o3p4q5r6s7t8u9v0w1x2y3z4a5b6c7"  // Another devnet placeholder
            ]
        }
    }
    
    /// Load token balances and information for all identities
    func loadTokensForIdentities() async {
        guard let tokenService = tokenService,
              let platformSdk = platformSDK else {
            print("TokenService or Platform SDK not available")
            return
        }
        
        // Create a simple SDK wrapper for TokenService
        // Stub implementation - PlatformSDKWrapper doesn't have sdkHandle yet
        let sdk = SimpleSDK(handle: nil)
        
        var allTokens: [TokenModel] = []
        
        // Discover available token IDs dynamically
        let availableTokenIds = await discoverAvailableTokenIds()
        print("🪙 Using \(availableTokenIds.count) discovered token IDs for balance queries")
        
        // For each identity, fetch their token balances
        for identity in identities {
            do {
                // Fetch token balances for this identity using discovered tokens
                let balances = try await tokenService.fetchTokenBalances(
                    sdk: sdk,
                    identityId: identity.idString,
                    tokenIds: availableTokenIds
                )
                
                // Fetch token info for this identity
                let tokenInfos = try await tokenService.fetchTokenInfos(
                    sdk: sdk,
                    identityId: identity.idString,
                    tokenIds: availableTokenIds
                )
                
                // Merge balance and info data into TokenModel objects
                for balance in balances {
                    if let tokenInfo = tokenInfos.first(where: { $0.tokenId == balance.tokenId }) {
                        let token = TokenModel(from: tokenInfo, balance: balance)
                        allTokens.append(token)
                    }
                }
                
            } catch {
                print("Failed to load tokens for identity \(identity.alias ?? identity.idString): \(error)")
            }
        }
        
        await MainActor.run {
            self.tokens = allTokens
        }
        
        // Save the fetched tokens to persistence
        await saveTokenBalances()
    }
    
    /// Refresh tokens for a specific identity
    func refreshTokensForIdentity(_ identity: IdentityModel) async {
        guard let tokenService = tokenService,
              let platformSdk = platformSDK else {
            return
        }
        
        // Create a simple SDK wrapper for TokenService
        // Stub implementation - PlatformSDKWrapper doesn't have sdkHandle yet
        let sdk = SimpleSDK(handle: nil)
        
        do {
            // Discover available token IDs dynamically
            let availableTokenIds = await discoverAvailableTokenIds()
            print("🪙 Refreshing tokens for identity using \(availableTokenIds.count) discovered token IDs")
            
            let balances = try await tokenService.fetchTokenBalances(
                sdk: sdk,
                identityId: identity.idString,
                tokenIds: availableTokenIds
            )
            
            let tokenInfos = try await tokenService.fetchTokenInfos(
                sdk: sdk,
                identityId: identity.idString,
                tokenIds: availableTokenIds
            )
            
            var updatedTokens = tokens.filter { token in
                !availableTokenIds.contains(token.id)
            }
            
            for balance in balances {
                if let tokenInfo = tokenInfos.first(where: { $0.tokenId == balance.tokenId }) {
                    let token = TokenModel(from: tokenInfo, balance: balance)
                    updatedTokens.append(token)
                }
            }
            
            await MainActor.run {
                self.tokens = updatedTokens
            }
            
            // Save the updated tokens to persistence
            await saveTokenBalances()
            
        } catch {
            showError(message: "Failed to refresh tokens: \(error.localizedDescription)")
        }
    }
    
    /// Get tokens for a specific identity
    func getTokensForIdentity(_ identity: IdentityModel) -> [TokenModel] {
        // For now, return all tokens
        // In a more sophisticated implementation, we'd track which tokens belong to which identity
        return tokens
    }
    
    // MARK: - Token Persistence Methods
    
    /// Load persisted token balances from SwiftData
    func loadPersistedTokens() async {
        guard let dataManager = _dataManager else { return }
        
        var allTokens: [TokenModel] = []
        
        for identity in identities {
            do {
                let identityData = identity.id
                
                let persistedBalances = try dataManager.fetchTokenBalances(identityId: identityData)
                
                for balance in persistedBalances {
                    // Create a basic TokenModel from persisted balance
                    let token = TokenModel(
                        id: balance.tokenId,
                        contractId: "unknown", // Would need to be stored/looked up
                        tokenPosition: 0, // Would need to be stored/looked up
                        name: nil,
                        symbol: nil,
                        decimals: nil,
                        totalSupply: nil,
                        balance: balance.balance,
                        frozenBalance: 0,
                        frozen: balance.frozen,
                        availableClaims: [],
                        priceInfo: nil,
                        status: nil
                    )
                    allTokens.append(token)
                }
            } catch {
                print("Failed to load persisted tokens for identity \(identity.alias ?? identity.idString): \(error)")
            }
        }
        
        await MainActor.run {
            self.tokens = allTokens
        }
        
        print("🪙 Loaded \(allTokens.count) persisted token balances")
    }
    
    /// Save token balances to SwiftData
    func saveTokenBalances() async {
        guard let dataManager = _dataManager else { return }
        
        // Group tokens by identity
        let tokensByIdentity = Dictionary(grouping: tokens) { token in
            // For now, assume all tokens belong to all identities
            // In a real implementation, this would be tracked properly
            identities.first?.id
        }
        
        for identity in identities {
            let identityData = identity.id
            
            do {
                // Prepare token balance data for this identity
                var tokenBalanceData: [(tokenId: String, balance: UInt64, frozen: Bool, tokenInfo: (name: String?, symbol: String?, decimals: Int32?)?)] = []
                
                for token in tokens {
                    tokenBalanceData.append((
                        tokenId: token.id,
                        balance: token.balance,
                        frozen: token.frozen,
                        tokenInfo: (
                            name: token.name,
                            symbol: token.symbol,
                            decimals: token.decimals.map { Int32($0) }
                        )
                    ))
                }
                
                try dataManager.saveTokenBalances(identityId: identityData, tokenBalances: tokenBalanceData)
                print("✅ Saved \(tokenBalanceData.count) token balances for identity \(identity.alias ?? identity.idString)")
                
            } catch {
                print("🔴 Failed to save token balances for identity \(identity.alias ?? identity.idString): \(error)")
            }
        }
    }
    
    func loadSampleIdentities() async {
        guard let dataManager = _dataManager else { return }
        
        // Add some sample local identities for testing
        let sampleIdentities = [
            IdentityModel(
                idString: "1111111111111111111111111111111111111111111111111111111111111111",
                balance: 1000000000,
                isLocal: true,
                alias: "Alice"
            ),
            IdentityModel(
                idString: "2222222222222222222222222222222222222222222222222222222222222222",
                balance: 500000000,
                isLocal: true,
                alias: "Bob"
            ),
            IdentityModel(
                idString: "3333333333333333333333333333333333333333333333333333333333333333",
                balance: 250000000,
                isLocal: true,
                alias: "Charlie"
            )
        ].compactMap { $0 }
        
        // Save to persistence
        for identity in sampleIdentities {
            do {
                try dataManager.saveIdentity(identity)
            } catch {
                print("Error saving sample identity: \(error)")
            }
        }
        
        // Update published array
        identities = sampleIdentities
    }
    
    func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    func showSuccess(message: String) {
        successMessage = message
        showSuccess = true
    }
    
    func switchNetwork(to network: PlatformNetwork) async {
        guard let modelContext = modelContext else { return }
        
        // Clear current data
        identities.removeAll()
        contracts.removeAll()
        documents.removeAll()
        tokens.removeAll()
        
        // Update DataManager's current network
        _dataManager?.currentNetwork = network
        
        // Re-initialize SDK with new network
        do {
            isLoading = true
            
            // Create configuration for new network
            print("🔄 Switching Core SDK to network: \(network)")
            let dashNetwork = network.toDashNetwork()
            let coreConfig = try SPVConfigurationManager.shared.configuration(for: dashNetwork)
            let newCoreSDK = try DashSDK(configuration: coreConfig)
            coreSDK = newCoreSDK
            
            // Reinitialize Platform SDK with new network and Core context
            print("🔄 Switching Platform SDK to network: \(network)")
            do {
                let newPlatformSDK = try await PlatformSDKWrapper(network: network, coreSDK: newCoreSDK)
                platformSDK = newPlatformSDK
                
                // Recreate AssetLockBridge
                assetLockBridge = await AssetLockBridge(coreSDK: newCoreSDK, platformSDK: newPlatformSDK, walletService: WalletService.shared)
                print("✅ Platform SDK and AssetLockBridge updated for new network")
            } catch {
                print("🔴 Failed to switch Platform SDK to new network: \(error)")
                platformSDK = nil
                assetLockBridge = nil
            }
            
            // Update mock SDK for backward compatibility
            sdk = SDK()
            
            // Reload data for the new network
            await loadPersistedData()
            
            isLoading = false
            print("✅ Network switch completed")
            
        } catch {
            showError(message: "Failed to switch network: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    func addIdentity(_ identity: IdentityModel) {
        guard let dataManager = dataManager else { return }
        
        if !identities.contains(where: { $0.id == identity.id }) {
            identities.append(identity)
            
            // Save to persistence
            Task {
                do {
                    try dataManager.saveIdentity(identity)
                } catch {
                    print("Error saving identity: \(error)")
                }
            }
        }
    }
    
    func removeIdentity(_ identity: IdentityModel) {
        guard let dataManager = dataManager else { return }
        
        identities.removeAll { $0.id == identity.id }
        
        // Remove from persistence
        Task {
            do {
                try dataManager.deleteIdentity(withId: identity.id)
            } catch {
                print("Error deleting identity: \(error)")
            }
        }
    }
    
    func updateIdentityBalance(id: Data, newBalance: UInt64) {
        guard let dataManager = dataManager else { return }
        
        if let index = identities.firstIndex(where: { $0.id == id }) {
            var identity = identities[index]
            identity = IdentityModel(
                id: identity.id,
                balance: newBalance,
                isLocal: identity.isLocal,
                alias: identity.alias,
                type: identity.type,
                privateKeys: identity.privateKeys,
                votingPrivateKey: identity.votingPrivateKey,
                ownerPrivateKey: identity.ownerPrivateKey,
                payoutPrivateKey: identity.payoutPrivateKey,
                dppIdentity: identity.dppIdentity,
                publicKeys: identity.publicKeys
            )
            identities[index] = identity
            
            // Update in persistence
            Task {
                do {
                    try dataManager.saveIdentity(identity)
                } catch {
                    print("Error updating identity balance: \(error)")
                }
            }
        }
    }
    
    func addContract(_ contract: ContractModel) {
        guard let dataManager = dataManager else { return }
        
        if !contracts.contains(where: { $0.id == contract.id }) {
            contracts.append(contract)
            
            // Save to persistence
            Task {
                do {
                    try dataManager.saveContract(contract)
                } catch {
                    print("Error saving contract: \(error)")
                }
            }
        }
    }
    
    func addDocument(_ document: DocumentModel) {
        guard let dataManager = dataManager else { return }
        
        if !documents.contains(where: { $0.id == document.id }) {
            documents.append(document)
            
            // Save to persistence
            Task {
                do {
                    try dataManager.saveDocument(document)
                } catch {
                    print("Error saving document: \(error)")
                }
            }
        }
    }
    
    // MARK: - Data Statistics
    
    func getDataStatistics() async -> (identities: Int, documents: Int, contracts: Int, tokenBalances: Int)? {
        guard let dataManager = dataManager else { return nil }
        
        do {
            return try dataManager.getDataStatistics()
        } catch {
            print("Error getting data statistics: \(error)")
            return nil
        }
    }
}
