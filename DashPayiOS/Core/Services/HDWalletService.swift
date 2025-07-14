import Foundation
import CryptoKit
import SwiftDashCoreSDK
import KeyWalletFFISwift

// MARK: - DashNetwork Extension for KeyWallet

extension DashNetwork {
    var keyWalletNetwork: KeyWalletFFISwift.Network {
        switch self {
        case .mainnet:
            return .dash
        case .testnet:
            return .testnet
        case .regtest:
            return .regtest
        case .devnet:
            return .devnet
        }
    }
}

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
            // Use the global function from KeyWalletFFI module
            return try KeyWalletFFISwift.validateMnemonic(phrase: phrase, language: Language.english)
        } catch {
            print("Mnemonic validation failed: \(error)")
            return false
        }
    }
    
    // MARK: - Seed Operations
    
    static func mnemonicToSeed(_ mnemonic: [String], passphrase: String = "") throws -> Data {
        let phrase = mnemonic.joined(separator: " ")
        let mnemonicObj = try Mnemonic(phrase: phrase, language: .english)
        let seedBytes = mnemonicObj.toSeed(passphrase: passphrase)
        return Data(seedBytes)
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
    
    // MARK: - Key Derivation
    
    static func deriveExtendedPublicKey(
        seed: Data,
        network: DashNetwork,
        account: UInt32
    ) throws -> String {
        do {
            // Convert DashNetwork to KeyWalletFFI Network
            // Create HD wallet from seed using the correct network type
            let hdWallet = try HdWallet.fromSeed(seed: Array(seed), network: network.keyWalletNetwork)
            
            // Get account extended public key
            let accountXPub = try hdWallet.getAccountXpub(account: account)
            
            return accountXPub.xpub
        } catch {
            print("🔴 Failed to derive extended public key: \(error)")
            // Instead of generating mock xpub, throw an error
            // This prevents the chain of errors that leads to invalid addresses
            throw WalletError.derivationFailed
        }
    }
    
    static func deriveAddress(
        xpub: String,
        network: DashNetwork,
        change: Bool,
        index: UInt32
    ) throws -> String {
        do {
            // Create address generator with the correct network type
            let addressGenerator = AddressGenerator(network: network.keyWalletNetwork)
            
            // Create AccountXPub from the extended public key string
            // The derivation path will be filled in by the FFI when getting account xpub
            let accountXPub = AccountXPub(
                derivationPath: "", // Not needed for address generation from xpub
                xpub: xpub,
                pubKey: nil
            )
            
            // Generate the address
            let address = try addressGenerator.generate(
                accountXpub: accountXPub,
                external: !change,  // external=true for receive addresses, false for change
                index: index
            )
            
            return address.toString()
        } catch {
            print("🔴 Failed to derive address: \(error)")
            // Instead of generating mock addresses, throw an error
            // This prevents invalid addresses from being created and watched
            throw WalletError.derivationFailed
        }
    }
    
    static func deriveAddresses(
        xpub: String,
        network: DashNetwork,
        change: Bool,
        startIndex: UInt32,
        count: UInt32
    ) throws -> [String] {
        do {
            // Create address generator with the correct network type
            let addressGenerator = AddressGenerator(network: network.keyWalletNetwork)
            
            // Create AccountXPub from string
            let accountXPub = AccountXPub(
                derivationPath: "", // Path is not needed for address generation
                xpub: xpub,
                pubKey: nil
            )
            
            // Generate addresses in range
            let addresses = try addressGenerator.generateRange(
                accountXpub: accountXPub,
                external: !change,  // external=true for receive addresses, false for change
                start: startIndex,
                count: count
            )
            
            return addresses.map { $0.toString() }
        } catch {
            print("Failed to derive addresses: \(error)")
            // Fallback to generating individual addresses
            return try (startIndex..<(startIndex + count)).map { index in
                try deriveAddress(xpub: xpub, network: network, change: change, index: index)
            }
        }
    }
    
    // MARK: - Helpers
    
    // MARK: - BIP44 Helpers
    
    static func derivationPath(network: DashNetwork, account: UInt32, change: Bool, index: UInt32) -> String {
        let coinType: UInt32 = network == .mainnet ? 5 : 1  // 5 for Dash mainnet, 1 for testnet
        let changeValue: UInt32 = change ? 1 : 0
        return "m/44'/\(coinType)'/\(account)'/\(changeValue)/\(index)"
    }
    
    static func accountDerivationPath(network: DashNetwork, account: UInt32) -> String {
        let coinType: UInt32 = network == .mainnet ? 5 : 1
        return "m/44'/\(coinType)'/\(account)'"
    }
    
    // MARK: - Account Discovery
    
    static func discoverAccounts(
        seed: Data,
        network: DashNetwork,
        maxAccounts: UInt32 = 10
    ) throws -> [(accountIndex: UInt32, xpub: String)] {
        var accounts: [(UInt32, String)] = []
        
        for accountIndex in 0..<maxAccounts {
            let xpub = try deriveExtendedPublicKey(
                seed: seed,
                network: network,
                account: accountIndex
            )
            
            // In production, would check if account has been used
            // For now, create the first account by default
            accounts.append((accountIndex, xpub))
            
            // Stop after first account for now
            break
        }
        
        return accounts
    }
    
    // MARK: - Address Verification
    
    static func isValidAddress(_ address: String, network: DashNetwork) -> Bool {
        // Enhanced address validation
        // Check for mock addresses and reject them
        if address.contains("Mock") {
            print("🔴 Rejecting mock address: \(address)")
            return false
        }
        
        // Validate address format based on network
        switch network {
        case .mainnet:
            // Mainnet addresses start with 'X' and are 34 characters long
            return address.hasPrefix("X") && address.count == 34 && address.allSatisfy { $0.isASCII }
        case .testnet:
            // Testnet addresses start with 'y' and are 34 characters long
            return address.hasPrefix("y") && address.count == 34 && address.allSatisfy { $0.isASCII }
        case .devnet, .regtest:
            // Devnet/regtest addresses start with 'y' and are 34 characters long
            return address.hasPrefix("y") && address.count == 34 && address.allSatisfy { $0.isASCII }
        }
    }
    
    // MARK: - Advanced Key Derivation
    
    static func derivePrivateKey(
        seed: Data,
        network: DashNetwork,
        account: UInt32,
        change: Bool,
        index: UInt32
    ) -> Data? {
        do {
            // Create HD wallet from seed
            let hdWallet = try HdWallet.fromSeed(seed: Array(seed), network: network.keyWalletNetwork)
            
            // Get private key for specific derivation path
            let derivePath = derivationPath(network: network, account: account, change: change, index: index)
            
            // Note: This is simplified - in production would use proper key derivation
            // The KeyWalletFFI doesn't expose raw private key derivation in the current interface
            // This would require additional FFI methods or using the seed directly
            
            return nil // Placeholder - implement when FFI supports it
        } catch {
            print("Private key derivation failed: \(error)")
            return nil
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
            return "Failed to encrypt wallet seed"
        case .decryptionFailed:
            return "Failed to decrypt wallet seed"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .invalidSeed:
            return "Invalid seed data"
        case .derivationFailed:
            return "Failed to derive keys"
        case .noContext:
            return "Storage context not available"
        case .duplicateWallet:
            return "A wallet with this seed already exists"
        case .notConnected:
            return "Wallet is not connected"
        case .invalidState:
            return "Invalid wallet state"
        case .noActiveWallet:
            return "No active wallet selected"
        case .noAccounts:
            return "Wallet has no accounts"
        case .connectionFailed:
            return "Failed to connect to Dash network"
        case .fileSystemError(let message):
            return message
        }
    }
}