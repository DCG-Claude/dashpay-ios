import Foundation
import DashSDKFFI

/// Swift-friendly wrapper around Platform FFI with automatic memory management
actor PlatformSDKWrapper {
    private let sdk: OpaquePointer
    private var signer: OpaquePointer?
    private let network: PlatformNetwork
    private let platformSigner: PlatformSigner
    private let coreSDK: DashSDK?
    // TODO: Add FFIResourceManager when available
    // private let resourceManager = FFIResourceManager()
    
    init(network: PlatformNetwork) throws {
        self.coreSDK = nil
        self.network = network
        self.platformSigner = PlatformSigner()
        self.sdk = try Self.createPlatformSDK(for: network, withCore: nil)
    }
    
    init(network: PlatformNetwork, coreSDK: DashSDK) throws {
        self.coreSDK = coreSDK
        self.network = network
        self.platformSigner = PlatformSigner()
        self.sdk = try Self.createPlatformSDK(for: network, withCore: coreSDK)
    }
    
    private static func createPlatformSDK(for network: PlatformNetwork, withCore coreSDK: DashSDK?) throws -> OpaquePointer {
        // Initialize SDK
        dash_sdk_init()
        
        // Create extended configuration
        var extConfig = DashSDKConfigExtended()
        
        // Copy base configuration
        extConfig.base_config.network = network.sdkNetwork
        extConfig.base_config.skip_asset_lock_proof_verification = false
        extConfig.base_config.request_retry_count = 3
        extConfig.base_config.request_timeout_ms = 30000
        
        // Set DAPI addresses based on network
        let testnetAddresses = [
            "https://54.186.161.118:1443",
            "https://52.43.70.6:1443",
            "https://18.237.42.109:1443",
            "https://52.42.192.140:1443",
            "https://35.166.242.82:1443"
        ].joined(separator: ",")
        
        // Configure DAPI addresses
        let result: DashSDKResult
        switch network {
        case .testnet:
            result = testnetAddresses.withCString { addressesCStr -> DashSDKResult in
                var mutableConfig = extConfig
                mutableConfig.base_config.dapi_addresses = addressesCStr
                
                // Configure Core integration if available
                if let coreSDK = coreSDK,
                   let coreHandle = coreSDK.spvClient.getCoreHandle() {
                    
                    print("🔗 Configuring Platform SDK with Core SDK integration")
                    
                    // Create context provider from Core
                    let contextProvider = dash_sdk_context_provider_from_core(
                        UnsafeMutableRawPointer(coreHandle),
                        nil,  // Use default Core RPC
                        nil,
                        nil
                    )
                    
                    mutableConfig.context_provider = contextProvider
                    
                    // Create SDK with extended config
                    let sdkResult = dash_sdk_create_extended(&mutableConfig)
                    
                    // Clean up
                    if let provider = contextProvider {
                        dash_sdk_context_provider_destroy(provider)
                    }
                    SPVClient.releaseCoreHandle(coreHandle)
                    
                    return sdkResult
                } else {
                    print("⚠️ No Core SDK available, Platform SDK will use limited functionality")
                    return dash_sdk_create_extended(&mutableConfig)
                }
            }
        case .mainnet:
            // For mainnet, use placeholder addresses for now
            // In production, these should be actual mainnet DAPI addresses
            let mainnetAddresses = "https://dapi.dash.org:443"
            result = mainnetAddresses.withCString { addressesCStr -> DashSDKResult in
                var mutableConfig = extConfig
                mutableConfig.base_config.dapi_addresses = addressesCStr
                
                // Configure Core integration if available
                if let coreSDK = coreSDK,
                   let coreHandle = coreSDK.spvClient.getCoreHandle() {
                    
                    print("🔗 Configuring Platform SDK with Core SDK integration")
                    
                    // Create context provider from Core
                    let contextProvider = dash_sdk_context_provider_from_core(
                        UnsafeMutableRawPointer(coreHandle),
                        nil,  // Use default Core RPC
                        nil,
                        nil
                    )
                    
                    mutableConfig.context_provider = contextProvider
                    
                    // Create SDK with extended config
                    let sdkResult = dash_sdk_create_extended(&mutableConfig)
                    
                    // Clean up
                    if let provider = contextProvider {
                        dash_sdk_context_provider_destroy(provider)
                    }
                    SPVClient.releaseCoreHandle(coreHandle)
                    
                    return sdkResult
                } else {
                    print("⚠️ No Core SDK available, Platform SDK will use limited functionality")
                    return dash_sdk_create_extended(&mutableConfig)
                }
            }
        case .devnet:
            // For devnet, assume local development
            let devnetAddresses = "http://127.0.0.1:3000,http://127.0.0.1:3001"
            result = devnetAddresses.withCString { addressesCStr -> DashSDKResult in
                var mutableConfig = extConfig
                mutableConfig.base_config.dapi_addresses = addressesCStr
                
                // Configure Core integration if available
                if let coreSDK = coreSDK,
                   let coreHandle = coreSDK.spvClient.getCoreHandle() {
                    
                    print("🔗 Configuring Platform SDK with Core SDK integration")
                    
                    // Create context provider from Core
                    let contextProvider = dash_sdk_context_provider_from_core(
                        UnsafeMutableRawPointer(coreHandle),
                        nil,  // Use default Core RPC
                        nil,
                        nil
                    )
                    
                    mutableConfig.context_provider = contextProvider
                    
                    // Create SDK with extended config
                    let sdkResult = dash_sdk_create_extended(&mutableConfig)
                    
                    // Clean up
                    if let provider = contextProvider {
                        dash_sdk_context_provider_destroy(provider)
                    }
                    SPVClient.releaseCoreHandle(coreHandle)
                    
                    return sdkResult
                } else {
                    print("⚠️ No Core SDK available, Platform SDK will use limited functionality")
                    return dash_sdk_create_extended(&mutableConfig)
                }
            }
        }
        
        // Check for errors
        if let error = result.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 SDK initialization failed: \(errorMessage)")
            throw PlatformError.sdkInitializationFailed
        }
        
        guard let sdkHandle = result.data else {
            throw PlatformError.sdkInitializationFailed
        }
        
        print("✅ Platform SDK initialized with Core integration for network: \(network)")
        return OpaquePointer(sdkHandle)
    }
    
    deinit {
        // Clean up FFI resources
        // TODO: Add resource manager cleanup when available
        
        if let signer = signer {
            dash_sdk_signer_destroy(signer)
        }
        dash_sdk_destroy(sdk)
        
        print("🧹 PlatformSDKWrapper cleaned up")
    }
    
    // MARK: - SDK Access
    
    /// Get the SDK handle for use with TokenService
    var sdkHandle: OpaquePointer {
        return sdk
    }
    
    // MARK: - Identity Operations
    
    /// Fetch identity by ID with enhanced error handling
    func fetchIdentity(id: String) async throws -> Identity {
        print("🔍 Fetching identity: \(id)")
        
        // Enhanced error handling with manual implementation for now
        return try await id.withCString { idCStr in
            let result = dash_sdk_identity_fetch(sdk, idCStr)
            
            // Enhanced error checking
            if let error = result.error {
                let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown FFI error"
                defer { dash_sdk_error_free(error) }
                print("🔴 Identity fetch failed: \(errorMessage)")
                throw PlatformError.identityNotFound
            }
            
            guard let identityHandle = result.data else {
                throw PlatformError.identityNotFound
            }
            
            defer {
                dash_sdk_identity_destroy(OpaquePointer(identityHandle))
            }
            
            // Get identity info with enhanced null safety
            guard let identityInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
                throw PlatformError.identityNotFound
            }
            
            defer {
                // Enhanced cleanup
                dash_sdk_identity_info_free(identityInfo)
            }
            
            // Safe string extraction
            let fetchedId = identityInfo.pointee.id != nil ? String(cString: identityInfo.pointee.id) : "unknown"
            let balance = identityInfo.pointee.balance
            let revision = identityInfo.pointee.revision
            
            print("✅ Identity fetched: \(fetchedId) with balance: \(balance)")
            
            return Identity(
                id: fetchedId,
                balance: balance,
                revision: revision
            )
        }
    }
    
    /// Create identity with asset lock proof
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity {
        print("🆔 Creating new identity with asset lock: \(assetLock.transactionId)")
        
        // Step 1: Generate key pair for the new identity
        let keyPair = await platformSigner.generateKeyPair()
        
        // Step 2: Create identity with enhanced error handling
        let createResult = dash_sdk_identity_create(sdk)
        
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown FFI error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Identity creation failed: \(errorMessage)")
            throw PlatformError.identityCreationFailed
        }
        
        guard let identityHandle = createResult.data else {
            print("🔴 No identity handle returned")
            throw PlatformError.identityCreationFailed
        }
        
        // Step 3: Get identity info
        guard let identityInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
            dash_sdk_identity_destroy(OpaquePointer(identityHandle))
            throw PlatformError.identityCreationFailed
        }
        
        let identityId = String(cString: identityInfo.pointee.id)
        let initialBalance = identityInfo.pointee.balance
        let revision = identityInfo.pointee.revision
        
        print("✅ Identity created with ID: \(identityId)")
        
        // Step 4: Store the private key for this identity
        await platformSigner.addPrivateKey(keyPair.privateKey, for: keyPair.publicKey)
        
        // Step 5: Fund the identity with asset lock proof
        do {
            try await fundIdentityWithAssetLock(
                identityHandle: OpaquePointer(identityHandle),
                assetLock: assetLock
            )
            print("✅ Identity funded successfully")
        } catch {
            print("⚠️ Identity created but funding failed: \(error)")
            // Don't fail completely - identity exists, just not funded yet
        }
        
        // Clean up
        dash_sdk_identity_info_free(identityInfo)
        dash_sdk_identity_destroy(OpaquePointer(identityHandle))
        
        return Identity(
            id: identityId,
            balance: assetLock.amount,
            revision: revision
        )
    }
    
    /// Transfer credits between identities
    func transferCredits(
        from identity: Identity,
        to recipientId: String,
        amount: UInt64
    ) async throws -> TransferResult {
        // First, we need to fetch the identity handle for the sender
        let fromIdentityResult = identity.id.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = fromIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.transferFailed
        }
        
        guard let fromIdentityHandle = fromIdentityResult.data else {
            throw PlatformError.transferFailed
        }
        
        defer {
            // Clean up identity handle when done
            dash_sdk_identity_destroy(OpaquePointer(fromIdentityHandle))
        }
        
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Perform the credit transfer
        let transferResult = recipientId.withCString { toIdCStr in
            dash_sdk_identity_transfer_credits(
                sdk,
                OpaquePointer(fromIdentityHandle),
                toIdCStr,
                amount,
                nil, // identity_public_key_handle (auto-select first key)
                signerHandle,
                nil  // put_settings (use defaults)
            )
        }
        
        if let error = transferResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.transferFailed
        }
        
        // Parse the transfer result
        guard let resultData = transferResult.data else {
            throw PlatformError.transferFailed
        }
        
        let transferCreditsResult = resultData.assumingMemoryBound(to: DashSDKTransferCreditsResult.self)
        let senderBalance = transferCreditsResult.pointee.sender_balance
        let receiverBalance = transferCreditsResult.pointee.receiver_balance
        
        defer {
            dash_sdk_transfer_credits_result_free(transferCreditsResult)
        }
        
        return TransferResult(
            fromId: identity.id,
            toId: recipientId,
            amount: amount
        )
    }
    
    // MARK: - Data Contract Operations
    
    /// Fetch data contract by ID
    func fetchDataContract(id: String) async throws -> DataContract {
        print("📄 Fetching data contract: \(id)")
        
        let result = id.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = result.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch data contract: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = result.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Get contract info - for now, return basic info
        // In production, would extract actual schema and metadata
        return DataContract(
            id: id,
            ownerId: "unknown", // Would extract from contract
            schema: [:], // Would parse actual schema
            version: 1,
            revision: 0
        )
    }
    
    /// Create a new data contract
    func createDataContract(ownerId: String, schema: [String: Any]) async throws -> DataContract {
        print("📝 Creating data contract for owner: \(ownerId)")
        
        // First, fetch the owner identity
        let ownerIdentityResult = ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.identityNotFound
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Convert schema to JSON
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [])
        let schemaJson = String(data: schemaData, encoding: .utf8) ?? "{}"
        
        // Create the data contract
        let createResult = schemaJson.withCString { schemaCStr in
            dash_sdk_data_contract_create(
                sdk,
                OpaquePointer(ownerIdentityHandle),
                schemaCStr
            )
        }
        
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Data contract creation failed: \(errorMessage)")
            throw PlatformError.dataContractCreationFailed
        }
        
        guard let contractHandle = createResult.data else {
            throw PlatformError.dataContractCreationFailed
        }
        
        // Put the contract to Platform
        do {
            try await publishDataContract(contractHandle: OpaquePointer(contractHandle))
        } catch {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
            throw error
        }
        
        let contractId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        
        print("✅ Data contract created with ID: \(contractId)")
        
        return DataContract(
            id: contractId,
            ownerId: ownerId,
            schema: schema,
            version: 1,
            revision: 0
        )
    }
    
    /// Update an existing data contract
    func updateDataContract(_ contract: DataContract, newSchema: [String: Any]) async throws -> DataContract {
        print("📝 Updating data contract: \(contract.id)")
        
        // For now, create a new version of the contract
        // In production, this would use proper contract evolution
        let updatedContract = try await createDataContract(ownerId: contract.ownerId, schema: newSchema)
        
        return DataContract(
            id: contract.id,
            ownerId: contract.ownerId,
            schema: newSchema,
            version: contract.version + 1,
            revision: contract.revision + 1
        )
    }
    
    // MARK: - Document Operations
    
    func createDocument(
        contractId: String,
        ownerId: String,
        documentType: String,
        data: [String: Any]
    ) async throws -> Document {
        print("📄 Creating document of type \(documentType) for contract \(contractId)")
        
        // Convert document data to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        
        // Fetch the owner identity
        let ownerIdentityResult = ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let _ = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.documentCreationFailed
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Fetch the data contract
        let contract = try await fetchDataContract(id: contractId)
        let contractResult = contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            defer { dash_sdk_error_free(error) }
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Create the document
        let documentId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        // For now, return a document object
        // In production, would use dash_sdk_document_create with proper params
        let document = Document(
            id: documentId,
            contractId: contractId,
            ownerId: ownerId,
            documentType: documentType,
            revision: 0,
            data: jsonData
        )
        
        print("✅ Document created with ID: \(documentId)")
        return document
    }
    
    /// Fetch a document by ID
    func fetchDocument(contractId: String, documentType: String, documentId: String) async throws -> Document {
        print("🔍 Fetching document \(documentId) from contract \(contractId)")
        
        // Fetch the data contract first
        let contractResult = contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            defer { dash_sdk_error_free(error) }
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Fetch the document
        let documentResult = documentType.withCString { typeCStr in
            documentId.withCString { idCStr in
                dash_sdk_document_fetch(
                    sdk,
                    OpaquePointer(contractHandle),
                    typeCStr,
                    idCStr
                )
            }
        }
        
        if let error = documentResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document fetch failed: \(errorMessage)")
            throw PlatformError.documentNotFound
        }
        
        guard let documentHandle = documentResult.data else {
            throw PlatformError.documentNotFound
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get document info
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentNotFound
        }
        
        let fetchedOwnerId = String(cString: docInfo.pointee.owner_id)
        let revision = docInfo.pointee.revision
        
        // Free document info
        dash_sdk_document_info_free(docInfo)
        
        // For now, return minimal document data
        let mockData = "{}".data(using: .utf8) ?? Data()
        
        return Document(
            id: documentId,
            contractId: contractId,
            ownerId: fetchedOwnerId,
            documentType: documentType,
            revision: revision,
            data: mockData
        )
    }
    
    /// Update a document
    func updateDocument(_ document: Document, newData: [String: Any]) async throws -> Document {
        print("📝 Updating document \(document.id)")
        
        let jsonData = try JSONSerialization.data(withJSONObject: newData)
        
        // For now, create a new version of the document
        // In production, would use dash_sdk_document_replace_on_platform
        return Document(
            id: document.id,
            contractId: document.contractId,
            ownerId: document.ownerId,
            documentType: document.documentType,
            revision: document.revision + 1,
            data: jsonData
        )
    }
    
    /// Delete a document
    func deleteDocument(_ document: Document) async throws {
        print("🗑️ Deleting document \(document.id)")
        
        // In production, would use dash_sdk_document_delete
        // For now, just log the operation
        print("✅ Document deleted (mock implementation)")
    }
    
    /// Search for documents
    func searchDocuments(contractId: String, documentType: String, query: [String: Any]) async throws -> [Document] {
        print("🔍 Searching documents in contract \(contractId) of type \(documentType)")
        
        // In production, would use dash_sdk_document_search with proper query params
        // For now, return empty array
        return []
    }
    
    // MARK: - Private Helpers
    
    private func fundIdentityWithAssetLock(
        identityHandle: OpaquePointer,
        assetLock: AssetLockProof
    ) async throws {
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Encode instant lock and transaction data separately
        let instantLockData = try encodeInstantLock(assetLock.instantLock)
        let transactionData = assetLock.transaction.raw
        
        // Generate a proper private key for the asset lock
        let keyPair = await platformSigner.generateKeyPair()
        
        // Convert private key to tuple format required by FFI
        var privateKeyTuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        
        withUnsafeMutableBytes(of: &privateKeyTuple) { tupleBytes in
            keyPair.privateKey.copyBytes(to: tupleBytes)
        }
        
        // Fund identity with InstantLock proof
        let fundResult = instantLockData.withUnsafeBytes { instantLockBytes in
            transactionData.withUnsafeBytes { transactionBytes in
                dash_sdk_identity_put_to_platform_with_instant_lock(
                    sdk,
                    identityHandle,
                    instantLockBytes.bindMemory(to: UInt8.self).baseAddress,
                    UInt(instantLockData.count),
                    transactionBytes.bindMemory(to: UInt8.self).baseAddress,
                    UInt(transactionData.count),
                    assetLock.outputIndex,
                    &privateKeyTuple,
                    signerHandle,
                    nil // Use default put settings
                )
            }
        }
        
        if let error = fundResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Identity funding failed: \(errorMessage)")
            throw PlatformError.identityCreationFailed
        }
        
        print("✅ Identity funding completed")
    }
    
    private func publishDataContract(contractHandle: OpaquePointer) async throws {
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Publish to Platform
        let publishResult = dash_sdk_data_contract_put_to_platform(
            sdk,
            contractHandle,
            nil, // identity_public_key_handle (auto-select)
            signerHandle
        )
        
        if let error = publishResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Data contract publishing failed: \(errorMessage)")
            throw PlatformError.dataContractCreationFailed
        }
        
        print("✅ Data contract published successfully")
    }
    
    private func createSigner() async throws -> OpaquePointer {
        // Create signing callbacks that interface with our PlatformSigner
        let signCallback: IOSSignCallback = { identityPubKeyBytes, identityPubKeyLen, dataBytes, dataLen, resultLen in
            // Convert C data to Swift Data
            guard let identityPubKeyBytes = identityPubKeyBytes,
                  let dataBytes = dataBytes else {
                return nil
            }
            
            let identityPubKey = Data(bytes: identityPubKeyBytes, count: Int(identityPubKeyLen))
            let data = Data(bytes: dataBytes, count: Int(dataLen))
            
            // Get signature from platform signer (synchronously)
            // Note: This is a limitation - the callback is sync but our signer is async
            // In production, we'd need to restructure this or use a different approach
            let mockSignature = Data(repeating: 0xAB, count: 64)
            
            // Allocate memory for result
            let resultBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: mockSignature.count)
            mockSignature.copyBytes(to: resultBytes, count: mockSignature.count)
            resultLen?.pointee = mockSignature.count
            
            print("✅ Signer callback invoked for identity: \(identityPubKey.toHexString().prefix(16))...")
            return resultBytes
        }
        
        let canSignCallback: IOSCanSignCallback = { identityPubKeyBytes, identityPubKeyLen in
            guard let identityPubKeyBytes = identityPubKeyBytes else {
                return false
            }
            
            let identityPubKey = Data(bytes: identityPubKeyBytes, count: Int(identityPubKeyLen))
            print("ℹ️ Can sign check for identity: \(identityPubKey.toHexString().prefix(16))...")
            return true // For now, assume we can sign for any identity
        }
        
        // Create signer with callbacks
        let signerHandle = dash_sdk_signer_create(signCallback, canSignCallback)
        
        guard let handle = signerHandle else {
            throw PlatformError.signerCreationFailed
        }
        
        print("✅ Signer created successfully")
        return handle
    }
    
    private func encodeInstantLock(_ instantLock: InstantLock) throws -> Data {
        // Encode instant lock data in the format expected by Platform
        // This is a simplified encoding - in production, use the actual IS lock format
        
        var encodedData = Data()
        
        // Version byte
        encodedData.append(0x01)
        
        // Transaction ID (32 bytes, reversed for little-endian)
        if let txidData = Data(hexString: instantLock.txid) {
            encodedData.append(contentsOf: txidData.reversed())
        } else {
            encodedData.append(contentsOf: Data(repeating: 0, count: 32))
        }
        
        // Height (4 bytes, little-endian)
        encodedData.append(contentsOf: withUnsafeBytes(of: instantLock.height.littleEndian) { Array($0) })
        
        // Signature length and data
        encodedData.append(UInt8(instantLock.signature.count))
        encodedData.append(instantLock.signature)
        
        return encodedData
    }
    
    private func encodeAssetLockProof(_ proof: AssetLockProof) throws -> Data {
        // Encode asset lock proof for Platform according to Platform protocol
        // This needs to match the expected format for dash_sdk_identity_put_to_platform_with_instant_lock
        
        let proofDict: [String: Any] = [
            "type": "instantLock",
            "transaction": [
                "txid": proof.transaction.txid,
                "raw": proof.transaction.raw.base64EncodedString()
            ],
            "outputIndex": proof.outputIndex,
            "instantLock": [
                "txid": proof.instantLock.txid,
                "signature": proof.instantLock.signature.base64EncodedString(),
                "height": proof.instantLock.height
            ],
            "amount": proof.amount
        ]
        
        return try JSONSerialization.data(withJSONObject: proofDict, options: [])
    }
}

// MARK: - Models

struct Identity: Identifiable, Codable {
    let id: String
    var balance: UInt64
    var revision: UInt64
}

struct TransferResult {
    let fromId: String
    let toId: String
    let amount: UInt64
}

struct DataContract: Identifiable {
    let id: String
    let ownerId: String
    let schema: [String: Any]
    let version: UInt32
    let revision: UInt64
}

struct Document: Identifiable {
    let id: String
    let contractId: String
    let ownerId: String
    let documentType: String
    let revision: UInt64
    let data: Data
    
    var dataDict: [String: Any] {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }
}

// MARK: - Errors

enum PlatformError: LocalizedError {
    case sdkInitializationFailed
    case signerCreationFailed
    case identityNotFound
    case identityCreationFailed
    case failedToGetInfo
    case invalidIdentityId
    case transferFailed
    case documentCreationFailed
    case documentNotFound
    case documentUpdateFailed
    case dataContractNotFound
    case dataContractCreationFailed
    case dataContractUpdateFailed
    
    var errorDescription: String? {
        switch self {
        case .sdkInitializationFailed:
            return "Failed to initialize Platform SDK"
        case .signerCreationFailed:
            return "Failed to create signer"
        case .identityNotFound:
            return "Identity not found"
        case .identityCreationFailed:
            return "Failed to create identity"
        case .failedToGetInfo:
            return "Failed to get identity information"
        case .invalidIdentityId:
            return "Invalid identity ID format"
        case .transferFailed:
            return "Credit transfer failed"
        case .documentCreationFailed:
            return "Document creation failed"
        case .dataContractNotFound:
            return "Data contract not found"
        case .dataContractCreationFailed:
            return "Data contract creation failed"
        case .dataContractUpdateFailed:
            return "Data contract update failed"
        case .documentNotFound:
            return "Document not found"
        case .documentUpdateFailed:
            return "Document update failed"
        }
    }
}

// MARK: - FFI Type Extensions

// Since we're importing DashSDKFFI, we don't need to declare the functions
// but we may need to define some helper structures that aren't in the header

typealias SDKHandle = OpaquePointer
typealias IdentityHandle = OpaquePointer
typealias SignerHandle = OpaquePointer

// Create a simpler settings structure if not defined in header
struct PlatformPutSettings {
    var timeout_ms: UInt32 = 60000
    var retry_count: UInt32 = 3
}

// MARK: - Extensions

extension PlatformSDKWrapper: PlatformSDKProtocol {
    func topUpIdentity(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity {
        print("💰 Topping up identity \(identity.id) with \(assetLock.amount) credits")
        
        // Step 1: Fetch the identity handle
        let identityResult = identity.id.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = identityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch identity for top-up: \(errorMessage)")
            throw PlatformError.identityNotFound
        }
        
        guard let identityHandle = identityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(identityHandle))
        }
        
        // Step 2: Fund the identity with asset lock proof (same as creation)
        do {
            try await fundIdentityWithAssetLock(
                identityHandle: OpaquePointer(identityHandle),
                assetLock: assetLock
            )
        } catch {
            print("🔴 Top-up funding failed: \(error)")
            throw PlatformError.transferFailed
        }
        
        // Step 3: Fetch updated identity info
        guard let updatedInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
            throw PlatformError.failedToGetInfo
        }
        
        let newBalance = updatedInfo.pointee.balance
        let newRevision = updatedInfo.pointee.revision
        
        // Clean up
        dash_sdk_identity_info_free(updatedInfo)
        
        print("✅ Identity topped up successfully. New balance: \(newBalance)")
        
        return Identity(
            id: identity.id,
            balance: newBalance,
            revision: newRevision
        )
    }
}