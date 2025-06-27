import Foundation
import SwiftData
import DashSDKFFI

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
    
    public init(network: DashSDKFFI.DashSDKNetwork) throws {
        // Mock initialization with network
        self.init()
    }
    
    public static func initialize() {
        // Mock SDK initialization
    }
}

public struct IdentitiesAPI {
    public func fetchBalances(ids: [Data]) throws -> [Data: UInt64] {
        // Mock implementation
        return ids.reduce(into: [:]) { result, id in
            result[id] = UInt64.random(in: 0...1000000)
        }
    }
    
    public func get(id: String) throws -> SDKIdentity? {
        // Mock implementation - convert string ID to Data and create a mock identity
        guard let idData = Data(hexString: id) ?? Data.identifier(fromBase58: id),
              idData.count == 32 else {
            throw SDKError.invalidParameter("Invalid identity ID format")
        }
        
        // Return a mock identity
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
    
    private let testSigner = TestSigner()
    private var dataManager: DataManager?
    private var modelContext: ModelContext?
    
    // Token system integration
    @Published var tokenService: TokenService?
    @Published var platformSigner: PlatformSigner?
    
    init() {
        // Load saved network preference or use default
        if let savedNetwork = UserDefaults.standard.string(forKey: "currentNetwork"),
           let network = PlatformNetwork(rawValue: savedNetwork) {
            self.currentNetwork = network
        } else {
            self.currentNetwork = .testnet
        }
    }
    
    func initializeSDK(modelContext: ModelContext) {
        // Save the model context for later use
        self.modelContext = modelContext
        
        // Initialize DataManager
        self.dataManager = DataManager(modelContext: modelContext, currentNetwork: currentNetwork)
        
        Task { @MainActor in
            do {
                isLoading = true
                print("🔄 Initializing Dash SDK components...")
                
                // Step 1: Initialize Core SDK first
                print("🔧 Initializing Core SDK...")
                let coreConfig = SPVClientConfiguration.testnet() // Use appropriate network config
                let coreSdk = try DashSDK(configuration: coreConfig)
                coreSDK = coreSdk
                print("✅ Core SDK initialized")
                
                // Step 2: Initialize Platform SDK with Core context
                print("🔧 Initializing Platform SDK with Core context...")
                let platformSdk = try await initializePlatformSDK(with: coreSdk)
                platformSDK = platformSdk
                print("✅ Platform SDK initialized")
                
                // Step 3: Create AssetLockBridge to connect Core and Platform
                print("🔧 Creating AssetLockBridge...")
                let bridge = AssetLockBridge(coreSDK: coreSdk, platformSDK: platformSdk)
                assetLockBridge = bridge
                print("✅ AssetLockBridge created")
                
                // Step 4: Initialize mock SDK for backward compatibility
                SDK.initialize()
                sdk = SDK()
                
                // Step 5: Initialize TokenService and PlatformSigner
                print("🪙 Initializing Token Service...")
                let signer = PlatformSigner()
                platformSigner = signer
                let tokenSvc = TokenService()
                tokenService = tokenSvc
                print("✅ Token Service initialized")
                
                // Step 6: Load persisted data
                print("📂 Loading persisted data...")
                await loadPersistedData()
                
                isLoading = false
                print("🎉 SDK initialization complete!")
                
            } catch {
                print("🔴 SDK initialization failed: \(error)")
                showError(message: "Failed to initialize SDK: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }
    
    private func initializePlatformSDK(with coreSDK: DashSDK) async throws -> PlatformSDKWrapper {
        print("🌐 Setting up Platform SDK with network: \(currentNetwork)")
        
        // Create Platform SDK wrapper with Core SDK integration
        let platformSDK = try PlatformSDKWrapper(network: currentNetwork, coreSDK: coreSDK)
        
        return platformSDK
    }
    
    func loadPersistedData() async {
        guard let dataManager = dataManager else { return }
        
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
    
    /// Load token balances and information for all identities
    func loadTokensForIdentities() async {
        guard let tokenService = tokenService,
              let platformSdk = platformSDK else {
            print("TokenService or Platform SDK not available")
            return
        }
        
        // Create a simple SDK wrapper for TokenService
        let sdkHandle = await platformSdk.sdkHandle
        let sdk = SimpleSDK(handle: sdkHandle)
        
        var allTokens: [TokenModel] = []
        
        // For each identity, fetch their token balances
        for identity in identities {
            do {
                // For now, use some example token contract IDs
                // In a real app, these would come from a registry or be discovered
                let exampleTokenIds = [
                    "AEzd9k8r8P3u8RGU5tGz8kXR9V5hN2J7K3M4P6Q8S1T2", // Example token ID
                    "BF2e9l9s9Q4v9SGV6uH9l9YS0W6iO3K8L4N5Q7R9T2U3"  // Another example token ID
                ]
                
                // Fetch token balances for this identity
                let balances = try await tokenService.fetchTokenBalances(
                    sdk: sdk,
                    identityId: identity.idString,
                    tokenIds: exampleTokenIds
                )
                
                // Fetch token info for this identity
                let tokenInfos = try await tokenService.fetchTokenInfos(
                    sdk: sdk,
                    identityId: identity.idString,
                    tokenIds: exampleTokenIds
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
        let sdkHandle = await platformSdk.sdkHandle
        let sdk = SimpleSDK(handle: sdkHandle)
        
        do {
            // Use the same example token IDs as above
            let exampleTokenIds = [
                "AEzd9k8r8P3u8RGU5tGz8kXR9V5hN2J7K3M4P6Q8S1T2",
                "BF2e9l9s9Q4v9SGV6uH9l9YS0W6iO3K8L4N5Q7R9T2U3"
            ]
            
            let balances = try await tokenService.fetchTokenBalances(
                sdk: sdk,
                identityId: identity.idString,
                tokenIds: exampleTokenIds
            )
            
            let tokenInfos = try await tokenService.fetchTokenInfos(
                sdk: sdk,
                identityId: identity.idString,
                tokenIds: exampleTokenIds
            )
            
            var updatedTokens = tokens.filter { token in
                !exampleTokenIds.contains(token.id)
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
        guard let dataManager = dataManager else { return }
        
        var allTokens: [TokenModel] = []
        
        for identity in identities {
            do {
                guard let identityData = identity.id else { continue }
                
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
        guard let dataManager = dataManager else { return }
        
        // Group tokens by identity
        let tokensByIdentity = Dictionary(grouping: tokens) { token in
            // For now, assume all tokens belong to all identities
            // In a real implementation, this would be tracked properly
            identities.first?.id
        }
        
        for identity in identities {
            guard let identityData = identity.id else { continue }
            
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
        guard let dataManager = dataManager else { return }
        
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
    
    func switchNetwork(to network: PlatformNetwork) async {
        guard let modelContext = modelContext else { return }
        
        // Clear current data
        identities.removeAll()
        contracts.removeAll()
        documents.removeAll()
        tokens.removeAll()
        
        // Update DataManager's current network
        dataManager?.currentNetwork = network
        
        // Re-initialize SDK with new network
        do {
            isLoading = true
            
            // Reinitialize Core SDK with new network
            print("🔄 Switching Core SDK to network: \(network)")
            let coreConfig = network == .testnet ? SPVClientConfiguration.testnet() : SPVClientConfiguration.mainnet()
            let newCoreSDK = try DashSDK(configuration: coreConfig)
            coreSDK = newCoreSDK
            
            // Reinitialize Platform SDK with new network and Core context
            print("🔄 Switching Platform SDK to network: \(network)")
            let newPlatformSDK = try PlatformSDKWrapper(network: network, coreSDK: newCoreSDK)
            platformSDK = newPlatformSDK
            
            // Recreate AssetLockBridge
            assetLockBridge = AssetLockBridge(coreSDK: newCoreSDK, platformSDK: newPlatformSDK)
            
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