import Foundation
import DashSDKFFI

/// Service for handling all token operations using Platform SDK FFI
class TokenService: ObservableObject {
    
    // MARK: - Error Types
    
    enum TokenServiceError: LocalizedError {
        case sdkNotInitialized
        case invalidIdentity
        case invalidTokenContract
        case invalidAmount
        case invalidRecipient
        case operationFailed(String)
        case jsonParsingFailed
        case insufficientBalance
        case tokenNotFound
        case authorizationRequired
        case contractNotFound
        
        var errorDescription: String? {
            switch self {
            case .sdkNotInitialized:
                return "Platform SDK is not initialized"
            case .invalidIdentity:
                return "Invalid identity provided"
            case .invalidTokenContract:
                return "Invalid token contract"
            case .invalidAmount:
                return "Invalid amount specified"
            case .invalidRecipient:
                return "Invalid recipient identity"
            case .operationFailed(let message):
                return "Token operation failed: \(message)"
            case .jsonParsingFailed:
                return "Failed to parse response data"
            case .insufficientBalance:
                return "Insufficient token balance"
            case .tokenNotFound:
                return "Token not found"
            case .authorizationRequired:
                return "Authorization required for this operation"
            case .contractNotFound:
                return "Token contract not found"
            }
        }
    }
    
    // MARK: - Token Data Models
    
    struct TokenBalance: Codable {
        let tokenId: String
        let balance: UInt64
        let frozen: Bool
        let contractId: String?
        let tokenPosition: UInt16?
        
        var formattedBalance: String {
            // This would use token decimals info when available
            return "\(balance)"
        }
    }
    
    struct TokenInfo: Codable {
        let tokenId: String
        let name: String?
        let symbol: String?
        let decimals: Int?
        let totalSupply: UInt64?
        let contractId: String
        let tokenPosition: UInt16
        let frozen: Bool
        let priceInfo: TokenPriceInfo?
    }
    
    struct TokenPriceInfo: Codable {
        let pricingType: String // "SinglePrice" or "SetPrices"
        let singlePrice: UInt64?
        let priceEntries: [TokenPriceEntry]?
    }
    
    struct TokenPriceEntry: Codable {
        let amount: UInt64
        let price: UInt64
    }
    
    struct TokenStatus: Codable {
        let tokenId: String
        let active: Bool
        let paused: Bool
        let emergencyMode: Bool
    }
    
    // MARK: - Private Properties
    
    private let resourceManager = FFIResourceManager()
    
    // MARK: - Public Methods
    
    // MARK: Token Balance Operations
    
    /// Fetch token balances for a specific identity
    func fetchTokenBalances(
        sdk: SimpleSDK,
        identityId: String,
        tokenIds: [String]
    ) async throws -> [TokenBalance] {
        guard let sdkHandle = sdk.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        let tokenIdsString = tokenIds.joined(separator: ",")
        
        return try await FFIHelpers.asyncFFICall { [weak self] in
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let result = dash_sdk_identity_fetch_token_balances(
                        sdkHandle,
                        identityId,
                        tokenIdsString
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.jsonParsingFailed
                        }
                        
                        let jsonString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        let balances = try self?.parseTokenBalances(from: jsonString) ?? []
                        continuation.resume(returning: balances)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Fetch token information for a specific identity
    func fetchTokenInfos(
        sdk: SimpleSDK,
        identityId: String,
        tokenIds: [String]
    ) async throws -> [TokenInfo] {
        guard let sdkHandle = sdk.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        let tokenIdsString = tokenIds.joined(separator: ",")
        
        return try await FFIHelpers.asyncFFICall { [weak self] in
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let result = dash_sdk_identity_fetch_token_infos(
                        sdkHandle,
                        identityId,
                        tokenIdsString
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.jsonParsingFailed
                        }
                        
                        let jsonString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        let tokenInfos = try self?.parseTokenInfos(from: jsonString) ?? []
                        continuation.resume(returning: tokenInfos)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Transfer Operations
    
    /// Transfer tokens between identities
    func transferTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        fromIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        recipientId: String,
        amount: UInt64,
        publicNote: String? = nil,
        privateNote: String? = nil,
        sharedNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = fromIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        // Convert recipient ID to bytes
        guard let recipientData = Data(base58: recipientId) else {
            throw TokenServiceError.invalidRecipient
        }
        
        let recipientBytes = Array(recipientData)
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenTransferParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        recipient_id: recipientBytes,
                        amount: amount,
                        public_note: publicNote,
                        private_encrypted_note: privateNote,
                        shared_encrypted_note: sharedNote
                    )
                    
                    let result = dash_sdk_token_transfer(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Mint Operations
    
    /// Mint new tokens
    func mintTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        ownerIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        recipientId: String? = nil,
        amount: UInt64,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = ownerIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        var recipientBytes: [UInt8]? = nil
        if let recipientId = recipientId,
           let recipientData = Data(base58: recipientId) {
            recipientBytes = Array(recipientData)
        }
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenMintParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        recipient_id: recipientBytes,
                        amount: amount,
                        public_note: publicNote
                    )
                    
                    let result = dash_sdk_token_mint(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Burn Operations
    
    /// Burn tokens from an identity
    func burnTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        ownerIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        amount: UInt64,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = ownerIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenBurnParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        amount: amount,
                        public_note: publicNote
                    )
                    
                    let result = dash_sdk_token_burn(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Claim Operations
    
    /// Claim tokens from a distribution
    func claimTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        claimerIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        distributionType: DashSDKTokenDistributionType = PreProgrammed,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = claimerIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenClaimParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        distribution_type: distributionType,
                        public_note: publicNote
                    )
                    
                    let result = dash_sdk_token_claim(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Freeze/Unfreeze Operations
    
    /// Freeze tokens for a specific identity
    func freezeTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        authorizedIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        targetIdentityId: String,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = authorizedIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        guard let targetData = Data(base58: targetIdentityId) else {
            throw TokenServiceError.invalidRecipient
        }
        
        let targetBytes = Array(targetData)
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenFreezeParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        target_identity_id: targetBytes,
                        public_note: publicNote
                    )
                    
                    let result = dash_sdk_token_freeze(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Unfreeze tokens for a specific identity
    func unfreezeTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        authorizedIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        targetIdentityId: String,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = authorizedIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        guard let targetData = Data(base58: targetIdentityId) else {
            throw TokenServiceError.invalidRecipient
        }
        
        let targetBytes = Array(targetData)
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenFreezeParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        target_identity_id: targetBytes,
                        public_note: publicNote
                    )
                    
                    let result = dash_sdk_token_unfreeze(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Purchase Operations
    
    /// Purchase tokens directly with credits
    func purchaseTokens(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        buyerIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        amount: UInt64,
        totalAgreedPrice: UInt64
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = buyerIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenPurchaseParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        amount: amount,
                        total_agreed_price: totalAgreedPrice
                    )
                    
                    let result = dash_sdk_token_purchase(
                        sdkHandle,
                        identityData,
                        &params,
                        nil, // identity_public_key_handle - auto-select
                        signerHandle,
                        nil, // put_settings - use defaults
                        nil  // state_transition_creation_options - use defaults
                    )
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Management Operations
    
    /// Destroy frozen funds for a specific identity
    func destroyFrozenFunds(
        sdk: SimpleSDK,
        signer: PlatformSigner,
        authorizedIdentity: IdentityModel,
        tokenContractId: String,
        tokenPosition: UInt16 = 0,
        frozenIdentityId: String,
        publicNote: String? = nil
    ) async throws -> String {
        guard let sdkHandle = sdk.handle,
              let signerHandle = signer.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        guard let identityData = authorizedIdentity.id else {
            throw TokenServiceError.invalidIdentity
        }
        
        guard let frozenData = Data(base58: frozenIdentityId) else {
            throw TokenServiceError.invalidRecipient
        }
        
        let frozenBytes = Array(frozenData)
        
        return try await FFIHelpers.asyncFFICall {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    var params = DashSDKTokenDestroyFrozenFundsParams(
                        token_contract_id: tokenContractId,
                        serialized_contract: nil,
                        serialized_contract_len: 0,
                        token_position: tokenPosition,
                        frozen_identity_id: frozenBytes,
                        public_note: publicNote
                    )
                    
                    let result = identityData.withUnsafeBytes { identityBytes in
                        return dash_sdk_token_destroy_frozen_funds(
                            sdkHandle,
                            identityBytes.bindMemory(to: UInt8.self).baseAddress!,
                            &params,
                            nil, // identity_public_key_handle - auto-select
                            signerHandle,
                            nil, // put_settings - use defaults
                            nil  // state_transition_creation_options - use defaults
                        )
                    }
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.operationFailed("No response data")
                        }
                        
                        let responseString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        continuation.resume(returning: responseString)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: Token Information Operations
    
    /// Get token contract information
    func getTokenContractInfo(
        sdk: SimpleSDK,
        tokenId: String
    ) async throws -> (contractId: String, tokenPosition: UInt16) {
        guard let sdkHandle = sdk.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        return try await FFIHelpers.asyncFFICall { [weak self] in
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let result = dash_sdk_token_get_contract_info(sdkHandle, tokenId)
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.jsonParsingFailed
                        }
                        
                        let jsonString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        let contractInfo = try self?.parseTokenContractInfo(from: jsonString) ?? ("", 0)
                        continuation.resume(returning: contractInfo)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Get token direct purchase prices
    func getTokenPrices(
        sdk: SimpleSDK,
        tokenIds: [String]
    ) async throws -> [String: TokenPriceInfo] {
        guard let sdkHandle = sdk.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        let tokenIdsString = tokenIds.joined(separator: ",")
        
        return try await FFIHelpers.asyncFFICall { [weak self] in
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let result = dash_sdk_token_get_direct_purchase_prices(sdkHandle, tokenIdsString)
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.jsonParsingFailed
                        }
                        
                        let jsonString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        let prices = try self?.parseTokenPrices(from: jsonString) ?? [:]
                        continuation.resume(returning: prices)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Get token statuses
    func getTokenStatuses(
        sdk: SimpleSDK,
        tokenIds: [String]
    ) async throws -> [String: TokenStatus] {
        guard let sdkHandle = sdk.handle else {
            throw TokenServiceError.sdkNotInitialized
        }
        
        let tokenIdsString = tokenIds.joined(separator: ",")
        
        return try await FFIHelpers.asyncFFICall { [weak self] in
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    let result = dash_sdk_token_get_statuses(sdkHandle, tokenIdsString)
                    
                    do {
                        if let error = result.error {
                            let errorMessage = FFIHelpers.extractErrorMessage(error)
                            dash_sdk_error_free(error)
                            throw TokenServiceError.operationFailed(errorMessage)
                        }
                        
                        guard result.data_type == String,
                              let dataPtr = result.data else {
                            throw TokenServiceError.jsonParsingFailed
                        }
                        
                        let jsonString = String(cString: dataPtr.assumingMemoryBound(to: CChar.self))
                        dash_sdk_string_free(dataPtr.assumingMemoryBound(to: CChar.self))
                        
                        let statuses = try self?.parseTokenStatuses(from: jsonString) ?? [:]
                        continuation.resume(returning: statuses)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Private JSON Parsing Methods
    
    private func parseTokenBalances(from jsonString: String) throws -> [TokenBalance] {
        guard let data = jsonString.data(using: .utf8) else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        // The response should be a dictionary of tokenId -> balance info
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return json.compactMap { (tokenId, value) in
            guard let balanceInfo = value as? [String: Any],
                  let balance = balanceInfo["balance"] as? UInt64 else {
                return nil
            }
            
            return TokenBalance(
                tokenId: tokenId,
                balance: balance,
                frozen: balanceInfo["frozen"] as? Bool ?? false,
                contractId: balanceInfo["contractId"] as? String,
                tokenPosition: balanceInfo["tokenPosition"] as? UInt16
            )
        }
    }
    
    private func parseTokenInfos(from jsonString: String) throws -> [TokenInfo] {
        guard let data = jsonString.data(using: .utf8) else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return json.compactMap { (tokenId, value) in
            guard let tokenInfo = value as? [String: Any],
                  let contractId = tokenInfo["contractId"] as? String,
                  let tokenPosition = tokenInfo["tokenPosition"] as? UInt16 else {
                return nil
            }
            
            var priceInfo: TokenPriceInfo? = nil
            if let priceData = tokenInfo["priceInfo"] as? [String: Any] {
                priceInfo = TokenPriceInfo(
                    pricingType: priceData["pricingType"] as? String ?? "SinglePrice",
                    singlePrice: priceData["singlePrice"] as? UInt64,
                    priceEntries: nil // Would need to parse this array if present
                )
            }
            
            return TokenInfo(
                tokenId: tokenId,
                name: tokenInfo["name"] as? String,
                symbol: tokenInfo["symbol"] as? String,
                decimals: tokenInfo["decimals"] as? Int,
                totalSupply: tokenInfo["totalSupply"] as? UInt64,
                contractId: contractId,
                tokenPosition: tokenPosition,
                frozen: tokenInfo["frozen"] as? Bool ?? false,
                priceInfo: priceInfo
            )
        }
    }
    
    private func parseTokenContractInfo(from jsonString: String) throws -> (String, UInt16) {
        guard let data = jsonString.data(using: .utf8) else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        guard let contractId = json["contractId"] as? String,
              let tokenPosition = json["tokenPosition"] as? UInt16 else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        return (contractId, tokenPosition)
    }
    
    private func parseTokenPrices(from jsonString: String) throws -> [String: TokenPriceInfo] {
        guard let data = jsonString.data(using: .utf8) else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return json.compactMapValues { value in
            guard let priceData = value as? [String: Any] else { return nil }
            
            return TokenPriceInfo(
                pricingType: priceData["pricingType"] as? String ?? "SinglePrice",
                singlePrice: priceData["singlePrice"] as? UInt64,
                priceEntries: nil // Would parse array if present
            )
        }
    }
    
    private func parseTokenStatuses(from jsonString: String) throws -> [String: TokenStatus] {
        guard let data = jsonString.data(using: .utf8) else {
            throw TokenServiceError.jsonParsingFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return json.compactMapValues { value in
            guard let statusData = value as? [String: Any] else { return nil }
            
            return TokenStatus(
                tokenId: "",
                active: statusData["active"] as? Bool ?? true,
                paused: statusData["paused"] as? Bool ?? false,
                emergencyMode: statusData["emergencyMode"] as? Bool ?? false
            )
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        resourceManager.cleanup()
    }
}

// MARK: - Data Extensions
// Base58 extensions are now available from Platform/Utils/Base58.swift