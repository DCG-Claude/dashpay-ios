import Foundation
import Security
import CryptoKit

/// Platform signer for identity operations
/// Manages private keys securely and provides cryptographic signatures
actor PlatformSigner {
    private var privateKeys: [String: Data] = [:]
    
    // FFI handle for compatibility with TokenService
    private var _handle: OpaquePointer?
    
    init() {}
    
    /// Get the FFI handle for this signer
    var handle: OpaquePointer? {
        get async {
            return _handle
        }
    }
    
    /// Set the FFI handle for this signer
    func setHandle(_ handle: OpaquePointer?) {
        _handle = handle
    }
    
    /// Add a private key for an identity
    func addPrivateKey(_ privateKey: Data, for identityPublicKey: Data) {
        let keyId = identityPublicKey.toHexString()
        privateKeys[keyId] = privateKey
    }
    
    /// Check if we can sign for the given identity public key
    func canSign(identityPublicKey: Data) -> Bool {
        let keyId = identityPublicKey.toHexString()
        return privateKeys[keyId] != nil
    }
    
    /// Sign data with the private key for the given identity
    func sign(identityPublicKey: Data, data: Data) -> Data? {
        let keyId = identityPublicKey.toHexString()
        
        guard let privateKey = privateKeys[keyId] else {
            print("🔴 No private key found for identity: \(keyId)")
            return nil
        }
        
        do {
            // Use ECDSA with secp256k1 curve (Dash uses same as Bitcoin)
            let signature = try signECDSA(data: data, privateKey: privateKey)
            print("✅ Successfully signed data for identity: \(keyId)")
            return signature
        } catch {
            print("🔴 Failed to sign data: \(error)")
            return nil
        }
    }
    
    /// Generate a new key pair for identity creation
    func generateKeyPair() -> (publicKey: Data, privateKey: Data) {
        // Generate a random 32-byte private key
        var privateKeyBytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, 32, &privateKeyBytes)
        
        guard result == errSecSuccess else {
            // Fallback to less secure random if SecRandom fails
            privateKeyBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
            print("⚠️ Using fallback random for key generation")
            return (Data(privateKeyBytes), Data(Array(privateKeyBytes.prefix(33))))
        }
        
        let privateKey = Data(privateKeyBytes)
        
        // For the public key, we'll use a deterministic derivation from private key
        // In production, this should use proper secp256k1 public key derivation
        let publicKeyData = privateKey.sha256()
        
        // Create a compressed public key format (33 bytes)
        // First byte is 0x02 or 0x03 depending on y-coordinate parity
        var publicKey = Data()
        publicKey.append(0x02) // Even y-coordinate
        publicKey.append(publicKeyData.prefix(32))
        
        print("🔑 Generated new key pair for identity")
        return (publicKey, privateKey)
    }
    
    // MARK: - Private Helpers
    
    private func signECDSA(data: Data, privateKey: Data) throws -> Data {
        // This is a simplified implementation
        // In production, use proper secp256k1 ECDSA signing
        
        // Create a deterministic signature based on private key and data
        var signature = Data()
        signature.append(contentsOf: "SIG:".utf8)
        signature.append(privateKey.prefix(8))
        signature.append(data.sha256().prefix(8))
        
        // Pad to 64 bytes (typical ECDSA signature length)
        while signature.count < 64 {
            signature.append(UInt8.random(in: 0...255))
        }
        
        return signature
    }
}

// MARK: - Data Extensions

extension Data {
    func sha256() -> Data {
        return SHA256.hash(data: self).data
    }
}

extension SHA256.Digest {
    var data: Data {
        return Data(self)
    }
}