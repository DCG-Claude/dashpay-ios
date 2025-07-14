import Foundation

/// Base58 encoding/decoding utility for Dash Platform identifiers
struct Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private static let base = 58
    
    /// Decode a Base58 string to Data
    static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }
        
        var result = [UInt8]()
        
        // Iterate directly over each character in the input string
        for char in string {
            guard let digit = alphabet.firstIndex(of: char) else {
                return nil
            }
            
            let digitValue = alphabet.distance(from: alphabet.startIndex, to: digit)
            
            // Convert the digit value and correctly accumulate across all bytes
            var carry = digitValue
            for j in 0..<result.count {
                let temp = Int(result[j]) * base + carry
                result[j] = UInt8(temp % 256)
                carry = temp / 256
            }
            
            // Handle multi-byte results by appending carry as needed
            while carry > 0 {
                result.append(UInt8(carry % 256))
                carry /= 256
            }
        }
        
        // Handle leading zeros
        var leadingZeros = 0
        for char in string {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }
        
        let zeros = Data(repeating: 0, count: leadingZeros)
        return zeros + Data(result.reversed())
    }
    
    /// Encode Data to a Base58 string
    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        
        var bytes = Array(data)
        var result = ""
        
        // Handle leading zeros
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 {
                leadingZeros += 1
            } else {
                break
            }
        }
        
        // Skip leading zeros for conversion
        bytes = Array(bytes.drop(while: { $0 == 0 }))
        
        while !bytes.isEmpty {
            var remainder = 0
            for i in 0..<bytes.count {
                let temp = remainder * 256 + Int(bytes[i])
                bytes[i] = UInt8(temp / base)
                remainder = temp % base
            }
            
            let char = alphabet[alphabet.index(alphabet.startIndex, offsetBy: remainder)]
            result = String(char) + result
            
            // Remove leading zeros from bytes
            while !bytes.isEmpty && bytes[0] == 0 {
                bytes.removeFirst()
            }
        }
        
        // Add leading '1's for each leading zero byte
        let leadingOnes = String(repeating: "1", count: leadingZeros)
        return leadingOnes + result
    }
}

// MARK: - Data Extension

extension Data {
    /// Initialize Data from a Base58 encoded string
    init?(base58: String) {
        guard let decoded = Base58.decode(base58) else {
            return nil
        }
        self = decoded
    }
    
    /// Get Base58 encoded string representation
    var base58EncodedString: String {
        return Base58.encode(self)
    }
}

// MARK: - String Extension

extension String {
    /// Convert Base58 string to Data
    var base58DecodedData: Data? {
        return Data(base58: self)
    }
}