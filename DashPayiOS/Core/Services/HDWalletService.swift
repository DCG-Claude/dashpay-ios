import Foundation
import CryptoKit
import SwiftDashCoreSDK
import SwiftDashSDK
import KeyWalletFFISwift

// MARK: - HD Wallet Service

class HDWalletService {
    
    // MARK: - Mnemonic Generation
    
    static func generateMnemonic(strength: Int = 128) throws -> [String] {
        // Use the proper BIP39 implementation from key-wallet-ffi
        // Word count: 12 words for 128-bit entropy, 24 words for 256-bit entropy
        let wordCount: UInt8 = strength == 256 ? 24 : 12
        let mnemonic = try Mnemonic.generate(language: .english, wordCount: wordCount)
        
        // Split the phrase into words
        let words = mnemonic.phrase().split(separator: " ").map { String($0) }
        return words
    }
    
    static func validateMnemonic(_ words: [String]) -> Bool {
        let phrase = words.joined(separator: " ")
        do {
            // Use KeyWalletFFISwift validation
            _ = try Mnemonic(phrase: phrase, language: .english)
            return true
        } catch {
            print("Mnemonic validation failed: \(error)")
            return false
        }
    }
    
    // MARK: - Seed Operations
    
    static func mnemonicToSeed(_ mnemonic: [String], passphrase: String = "") throws -> Data {
        let phrase = mnemonic.joined(separator: " ")
        // Use KeyWalletFFISwift to convert mnemonic to seed
        let mnemonicObj = try Mnemonic(phrase: phrase, language: .english)
        let seed = mnemonicObj.toSeed(passphrase: passphrase)
        return Data(seed)
    }
    
    static func seedHash(_ seed: Data) -> String {
        let hash = SHA256.hash(data: seed)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Encryption
    
    static func encryptSeed(_ seed: Data, password: String) throws -> Data {
        // Create a symmetric key from the password
        let passwordData = password.data(using: .utf8)!
        let hash = SHA256.hash(data: passwordData)
        let key = SymmetricKey(data: hash)
        
        // Encrypt the seed
        let sealedBox = try AES.GCM.seal(seed, using: key)
        
        // Return combined nonce + ciphertext + tag
        guard let combined = sealedBox.combined else {
            throw WalletError.encryptionFailed
        }
        
        return combined
    }
    
    static func decryptSeed(_ encryptedSeed: Data, password: String) throws -> Data {
        // Create a symmetric key from the password
        let passwordData = password.data(using: .utf8)!
        let hash = SHA256.hash(data: passwordData)
        let key = SymmetricKey(data: hash)
        
        // Decrypt the seed
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedSeed)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        return decryptedData
    }
    
    // MARK: - Key Derivation (Simplified for now)
    
    static func deriveExtendedPublicKey(
        seed: Data,
        network: DashNetwork,
        account: UInt32
    ) throws -> String {
        // Simplified stub implementation for build compatibility
        // TODO: Implement proper KeyWalletFFI integration
        let prefix = network == .mainnet ? "xpub" : "tpub"
        return "\(prefix)MockExtendedPublicKey\(account)"
    }
    
    static func deriveAddress(
        xpub: String,
        network: DashNetwork,
        change: Bool,
        index: UInt32
    ) throws -> String {
        // Simplified stub implementation for build compatibility
        // TODO: Implement proper KeyWalletFFI integration
        let prefix = network == .mainnet ? "X" : "y"
        let changeStr = change ? "1" : "0"
        return "\(prefix)MockAddress\(changeStr)\(index)"
    }
    
    static func deriveAddresses(
        xpub: String,
        network: DashNetwork,
        change: Bool,
        startIndex: UInt32,
        count: UInt32
    ) throws -> [String] {
        // Simplified stub implementation for build compatibility
        // TODO: Implement proper KeyWalletFFI integration
        return try (startIndex..<(startIndex + count)).map { index in
            try deriveAddress(xpub: xpub, network: network, change: change, index: index)
        }
    }
    
    // MARK: - Utility Functions
    
    static func derivationPath(
        network: DashNetwork,
        account: UInt32,
        change: Bool,
        index: UInt32
    ) -> String {
        let coinType: UInt32 = network == .mainnet ? 5 : 1
        let changeIndex: UInt32 = change ? 1 : 0
        return "m/44'/\(coinType)'/\(account)'/\(changeIndex)/\(index)"
    }
    
    static func derivePrivateKey(
        seed: Data,
        network: DashNetwork,
        account: UInt32,
        change: Bool,
        index: UInt32
    ) -> Data? {
        // Placeholder - private key derivation would require additional FFI methods
        print("Private key derivation not yet implemented")
        return nil
    }
    
    // MARK: - Address Validation
    
    static func isValidAddress(_ address: String, network: DashNetwork) -> Bool {
        // Basic Dash address validation
        // Mainnet addresses start with 'X' (P2PKH) or '7' (P2SH)
        // Testnet addresses start with 'y' (P2PKH) or '8'/'9' (P2SH)
        
        guard !address.isEmpty else { return false }
        
        // Check length (typical Dash address is 34 characters)
        guard address.count >= 26 && address.count <= 35 else { return false }
        
        switch network {
        case .mainnet:
            return address.first == "X" || address.first == "7"
        case .testnet, .devnet, .regtest:
            return address.first == "y" || address.first == "8" || address.first == "9"
        }
    }
}

// MARK: - DashNetwork Extension for KeyWalletFFI

extension DashNetwork {
    var keyWalletNetwork: KeyWalletFFISwift.Network {
        switch self {
        case .mainnet:
            return .dash
        case .testnet:
            return .testnet
        case .devnet:
            return .devnet
        case .regtest:
            return .regtest
        }
    }
}

// MARK: - Wallet Errors

enum WalletError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidMnemonic
    case invalidSeed
    case derivationFailed
    case noContext
    case duplicateWallet
    case notConnected
    case invalidState
    case noActiveWallet
    case noAccounts
    case connectionFailed
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt seed"
        case .decryptionFailed:
            return "Failed to decrypt seed"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .invalidSeed:
            return "Invalid seed data"
        case .derivationFailed:
            return "Failed to derive key"
        case .noContext:
            return "No model context available"
        case .duplicateWallet:
            return "Wallet already exists"
        case .notConnected:
            return "Not connected to network"
        case .invalidState:
            return "Invalid wallet state"
        case .noActiveWallet:
            return "No active wallet"
        case .noAccounts:
            return "No accounts available"
        case .connectionFailed:
            return "Connection failed"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}