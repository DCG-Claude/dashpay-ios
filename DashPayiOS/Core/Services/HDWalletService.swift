import Foundation
import CryptoKit
import CommonCrypto
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
            #if DEBUG
            print("Mnemonic validation failed: \(error)")
            #endif
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
    
    private static func deriveKeyFromPassword(password: Data, salt: Data, iterations: Int) throws -> Data {
        // Use PBKDF2 with SHA256 to derive a 32-byte key
        let keyLength = 32
        var derivedKey = Data(count: keyLength)
        
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw WalletError.encryptionFailed
        }
        
        return derivedKey
    }
    
    static func encryptSeed(_ seed: Data, password: String) throws -> Data {
        // Create a symmetric key from the password using PBKDF2
        guard let passwordData = password.data(using: .utf8) else {
            throw WalletError.encryptionFailed
        }
        
        // Generate a random salt
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        
        // Derive key using PBKDF2 with sufficient iterations
        let derivedKey = try deriveKeyFromPassword(password: passwordData, salt: salt, iterations: 100_000)
        let key = SymmetricKey(data: derivedKey)
        
        // Encrypt the seed
        let sealedBox = try AES.GCM.seal(seed, using: key)
        
        // Return salt + combined nonce + ciphertext + tag
        guard let combined = sealedBox.combined else {
            throw WalletError.encryptionFailed
        }
        
        // Prepend salt to the encrypted data
        var result = Data()
        result.append(salt)
        result.append(combined)
        
        return result
    }
    
    static func decryptSeed(_ encryptedSeed: Data, password: String) throws -> Data {
        // Create a symmetric key from the password using PBKDF2
        guard let passwordData = password.data(using: .utf8) else {
            throw WalletError.decryptionFailed
        }
        
        // Extract salt from the beginning of the encrypted data
        guard encryptedSeed.count > 32 else {
            throw WalletError.decryptionFailed
        }
        
        let salt = encryptedSeed.prefix(32)
        let encryptedData = encryptedSeed.dropFirst(32)
        
        // Derive key using PBKDF2 with the same parameters
        let derivedKey = try deriveKeyFromPassword(password: passwordData, salt: Data(salt), iterations: 100_000)
        let key = SymmetricKey(data: derivedKey)
        
        // Decrypt the seed
        let sealedBox = try AES.GCM.SealedBox(combined: Data(encryptedData))
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
        return BIP44.derivationPath(network: network, account: account, change: change, index: index)
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
        guard !address.isEmpty else { return false }
        
        // Try Base58Check validation first
        if isValidBase58CheckAddress(address, network: network) {
            return true
        }
        
        // TODO: Add Bech32 SegWit address validation when needed
        // For now, Dash primarily uses Base58Check addresses
        
        return false
    }
    
    private static func isValidBase58CheckAddress(_ address: String, network: DashNetwork) -> Bool {
        // Decode Base58 address
        guard let decoded = base58CheckDecode(address) else {
            return false
        }
        
        // Address must be exactly 25 bytes (1 version + 20 payload + 4 checksum)
        guard decoded.count == 25 else {
            return false
        }
        
        let versionByte = decoded[0]
        let payload = decoded[1...20]
        let providedChecksum = decoded[21...24]
        
        // Verify version byte matches network
        guard isValidVersionByte(versionByte, for: network) else {
            return false
        }
        
        // Compute double SHA-256 hash of version + payload
        let versionAndPayload = decoded[0...20]
        let hash1 = SHA256.hash(data: versionAndPayload)
        let hash2 = SHA256.hash(data: Data(hash1))
        let computedChecksum = Array(hash2.prefix(4))
        
        // Verify checksum
        return Array(providedChecksum) == computedChecksum
    }
    
    private static func isValidVersionByte(_ version: UInt8, for network: DashNetwork) -> Bool {
        switch network {
        case .mainnet:
            // Dash mainnet: P2PKH = 76 (0x4C, starts with 'X'), P2SH = 16 (0x10, starts with '7')
            return version == 0x4C || version == 0x10
        case .testnet, .devnet, .regtest:
            // Dash testnet: P2PKH = 140 (0x8C, starts with 'y'), P2SH = 19 (0x13, starts with '8' or '9')
            return version == 0x8C || version == 0x13
        }
    }
    
    private static func base58CheckDecode(_ string: String) -> [UInt8]? {
        // Base58 alphabet for Bitcoin/Dash
        let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        let base = UInt64(58)
        
        // Create character to value mapping
        var charToValue: [Character: UInt8] = [:]
        for (index, char) in base58Alphabet.enumerated() {
            charToValue[char] = UInt8(index)
        }
        
        // Count leading zeros
        var leadingZeros = 0
        for char in string {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }
        
        // Convert from Base58
        var result: UInt64 = 0
        for char in string {
            guard let value = charToValue[char] else {
                return nil // Invalid character
            }
            
            // Check for overflow
            let (newResult, overflow) = result.multipliedReportingOverflow(by: base)
            if overflow {
                return nil
            }
            
            let (finalResult, addOverflow) = newResult.addingReportingOverflow(UInt64(value))
            if addOverflow {
                return nil
            }
            
            result = finalResult
        }
        
        // Convert to bytes (big-endian)
        var bytes: [UInt8] = []
        var temp = result
        while temp > 0 {
            bytes.insert(UInt8(temp % 256), at: 0)
            temp /= 256
        }
        
        // Add leading zeros
        let leadingZeroBytes = Array(repeating: UInt8(0), count: leadingZeros)
        return leadingZeroBytes + bytes
    }
    
    // MARK: - BIP44 Derivation Path Utilities
    struct BIP44 {
        static func derivationPath(
            network: DashNetwork,
            account: UInt32,
            change: Bool,
            index: UInt32
        ) -> String {
            let coinType: String
            switch network {
            case .mainnet:
                coinType = "5"   // Dash mainnet coin type
            case .testnet, .devnet, .regtest:
                coinType = "1"   // Testnet coin type
            }
            
            let changeValue = change ? "1" : "0"
            return "m/44'/\(coinType)'/\(account)'/\(changeValue)/\(index)"
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
    case invalidAddress(String)
    case fileSystemError(String)
    case aggregateError([Error])
    case transactionFetchFailed(txid: String, underlyingError: Error)
    case unknownError
    
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
            return "Failed to connect to Dash network"
        case .invalidAddress(let message):
            return "Invalid address: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .aggregateError(let errors):
            let errorMessages = errors.map { $0.localizedDescription }.joined(separator: "; ")
            return "Multiple errors occurred: \(errorMessages)"
        case .transactionFetchFailed(let txid, let underlyingError):
            return "Failed to fetch transaction \(txid): \(underlyingError.localizedDescription)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}