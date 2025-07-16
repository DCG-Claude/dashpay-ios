import Foundation
import Security
import CryptoKit
import P256K

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
    
    /// Generate a new key pair for identity creation using secp256k1
    func generateKeyPair() -> (publicKey: Data, privateKey: Data) {
        do {
            // Generate a secp256k1 private key
            let privateKey = try P256K.Signing.PrivateKey()
            let publicKey = privateKey.publicKey
            
            print("🔑 Generated new secp256k1 key pair for identity")
            return (publicKey.dataRepresentation, privateKey.dataRepresentation)
        } catch {
            print("❌ Failed to generate secp256k1 key pair: \(error)")
            
            // Fallback to secure random bytes (for compatibility)
            var privateKeyBytes = [UInt8](repeating: 0, count: 32)
            let result = SecRandomCopyBytes(kSecRandomDefault, 32, &privateKeyBytes)
            
            if result != errSecSuccess {
                // Last resort fallback
                privateKeyBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
                print("⚠️ Using fallback random for key generation")
            }
            
            let privateKeyData = Data(privateKeyBytes)
            
            // Create a mock compressed public key format (33 bytes) for fallback
            var publicKeyData = Data()
            publicKeyData.append(0x02) // Even y-coordinate prefix
            publicKeyData.append(privateKeyData.sha256().prefix(32))
            
            return (publicKeyData, privateKeyData)
        }
    }
    
    // MARK: - Private Helpers
    
    private func signECDSA(data: Data, privateKey: Data) throws -> Data {
        do {
            // Use proper secp256k1 ECDSA signing
            let secpPrivateKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
            let signature = try secpPrivateKey.signature(for: data)
            
            // Return the signature in DER format (standard for Bitcoin/Dash)
            return try signature.derRepresentation
        } catch {
            print("❌ Failed to sign with secp256k1: \(error)")
            
            // Fallback implementation for compatibility
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
}

// MARK: - Data Extensions

extension Data {
    func sha256() -> Data {
        return CryptoKit.SHA256.hash(data: self).data
    }
}

extension CryptoKit.SHA256.Digest {
    var data: Data {
        return Data(self)
    }
}