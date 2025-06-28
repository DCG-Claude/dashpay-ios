import Foundation
import Security
import CryptoKit

/// Production-ready signer that uses iOS Keychain for secure key storage
class KeychainSigner: Signer {
    private let keyService = "com.dashpay.identity.keys"
    private let accessGroup: String?
    
    /// Initialize the Keychain signer
    /// - Parameter accessGroup: Optional keychain access group for sharing keys between apps
    init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }
    
    // MARK: - Signer Protocol Implementation
    
    func sign(identityPublicKey: Data, data: Data) -> Data? {
        // Convert public key to identity ID for keychain lookup
        let identityId = identityPublicKey.sha256Hash.hexString
        
        guard let privateKey = retrievePrivateKey(forIdentity: identityId) else {
            print("❌ KeychainSigner: No private key found for identity \(identityId)")
            return nil
        }
        
        do {
            // Sign the data using the private key
            let signature = try signData(data, with: privateKey)
            print("✅ KeychainSigner: Successfully signed data for identity \(identityId)")
            return signature
        } catch {
            print("❌ KeychainSigner: Failed to sign data for identity \(identityId): \(error)")
            return nil
        }
    }
    
    func canSign(identityPublicKey: Data) -> Bool {
        let identityId = identityPublicKey.sha256Hash.hexString
        return hasPrivateKey(forIdentity: identityId)
    }
    
    // MARK: - Key Management
    
    /// Store a private key securely in the Keychain
    /// - Parameters:
    ///   - privateKey: The private key data to store
    ///   - identityId: The identity ID to associate with the key
    /// - Returns: True if the key was stored successfully
    func storePrivateKey(_ privateKey: Data, forIdentity identityId: String) -> Bool {
        let query = baseKeychainQuery(forIdentity: identityId)
        var queryWithData = query
        queryWithData[kSecValueData] = privateKey
        queryWithData[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        
        // Delete any existing key first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(queryWithData as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ KeychainSigner: Private key stored for identity \(identityId)")
            return true
        } else {
            print("❌ KeychainSigner: Failed to store private key for identity \(identityId): \(status)")
            return false
        }
    }
    
    /// Remove a private key from the Keychain
    /// - Parameter identityId: The identity ID to remove the key for
    /// - Returns: True if the key was removed successfully or didn't exist
    func removePrivateKey(forIdentity identityId: String) -> Bool {
        let query = baseKeychainQuery(forIdentity: identityId)
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("✅ KeychainSigner: Private key removed for identity \(identityId)")
            return true
        } else {
            print("❌ KeychainSigner: Failed to remove private key for identity \(identityId): \(status)")
            return false
        }
    }
    
    /// Check if a private key exists for the given identity
    /// - Parameter identityId: The identity ID to check
    /// - Returns: True if a private key exists
    func hasPrivateKey(forIdentity identityId: String) -> Bool {
        let query = baseKeychainQuery(forIdentity: identityId)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Generate a new ECDSA key pair and store the private key in Keychain
    /// - Parameter identityId: The identity ID to associate with the new key
    /// - Returns: The public key data if successful
    func generateKeyPair(forIdentity identityId: String) -> Data? {
        do {
            // Generate a new P-256 private key (compatible with Bitcoin/Dash ECDSA)
            let privateKey = P256.Signing.PrivateKey()
            let publicKey = privateKey.publicKey
            
            // Store the private key in Keychain
            let privateKeyData = privateKey.rawRepresentation
            guard storePrivateKey(privateKeyData, forIdentity: identityId) else {
                return nil
            }
            
            // Return the public key data
            return publicKey.rawRepresentation
        } catch {
            print("❌ KeychainSigner: Failed to generate key pair for identity \(identityId): \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func baseKeychainQuery(forIdentity identityId: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: identityId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
    
    private func retrievePrivateKey(forIdentity identityId: String) -> Data? {
        let query = baseKeychainQuery(forIdentity: identityId)
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return keyData
        } else {
            return nil
        }
    }
    
    private func signData(_ data: Data, with privateKeyData: Data) throws -> Data {
        // Create a P-256 private key from the stored data
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
        
        // Sign the data
        let signature = try privateKey.signature(for: data)
        
        // Return the signature in DER format (standard for Bitcoin/Dash)
        return signature.derRepresentation
    }
}

// MARK: - Data Extensions

private extension Data {
    var sha256Hash: Data {
        return SHA256.hash(data: self).withUnsafeBytes { Data($0) }
    }
    
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Error Types

enum KeychainSignerError: Error {
    case keyNotFound
    case invalidKeyFormat
    case signingFailed
    case keychainError(OSStatus)
}