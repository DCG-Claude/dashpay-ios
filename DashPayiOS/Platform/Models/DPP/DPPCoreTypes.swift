import Foundation

// MARK: - Core Types based on DPP

/// 32-byte identifier used throughout the platform
typealias Identifier = Data

/// Revision number for versioning
typealias Revision = UInt64

/// Timestamp in milliseconds since Unix epoch
typealias TimestampMillis = UInt64

/// Credits amount
typealias Credits = UInt64

/// Key ID for identity public keys
typealias KeyID = UInt32

/// Key count
typealias KeyCount = KeyID

/// Block height on the platform chain
typealias BlockHeight = UInt64

/// Block height on the core chain
typealias CoreBlockHeight = UInt32

/// Epoch index
typealias EpochIndex = UInt16

/// Binary data
typealias BinaryData = Data

/// 32-byte hash
typealias Bytes32 = Data

/// Document name/type within a data contract
typealias DocumentName = String

/// Definition name for schema definitions
typealias DefinitionName = String

/// Group contract position
typealias GroupContractPosition = UInt16

/// Token contract position
typealias TokenContractPosition = UInt16

// MARK: - Helper Extensions

extension Data {
    /// Initialize Data from hex string
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "")
        let length = hex.count
        
        guard length % 2 == 0 else { return nil }
        
        var data = Data(capacity: length / 2)
        
        for i in stride(from: 0, to: length, by: 2) {
            let startIndex = hex.index(hex.startIndex, offsetBy: i)
            let endIndex = hex.index(startIndex, offsetBy: 2)
            let bytes = hex[startIndex..<endIndex]
            
            if let byte = UInt8(bytes, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
        }
        
        self = data
    }
    
    /// Create an Identifier from a hex string
    static func identifier(fromHex hexString: String) -> Identifier? {
        return Data(hexString: hexString)
    }
    
    /// Create an Identifier from a base58 string
    static func identifier(fromBase58 base58String: String) -> Identifier? {
        return Data(base58: base58String)
    }
    
    /// Convert to base58 string
    func toBase58String() -> String {
        return self.base58EncodedString
    }
    
}

// MARK: - Platform Value Type
/// Represents a value that can be stored in documents or contracts
enum PlatformValue: Codable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case float(Double)
    case string(String)
    case bytes(Data)
    case array([PlatformValue])
    case map([String: PlatformValue])
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    private enum ValueType: String, Codable {
        case null = "null"
        case bool = "bool"
        case integer = "integer"
        case unsignedInteger = "unsignedInteger"
        case float = "float"
        case string = "string"
        case bytes = "bytes"
        case array = "array"
        case map = "map"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        
        switch type {
        case .null:
            self = .null
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        case .integer:
            let value = try container.decode(Int64.self, forKey: .value)
            self = .integer(value)
        case .unsignedInteger:
            let value = try container.decode(UInt64.self, forKey: .value)
            self = .unsignedInteger(value)
        case .float:
            let value = try container.decode(Double.self, forKey: .value)
            self = .float(value)
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case .bytes:
            let value = try container.decode(Data.self, forKey: .value)
            self = .bytes(value)
        case .array:
            let value = try container.decode([PlatformValue].self, forKey: .value)
            self = .array(value)
        case .map:
            let value = try container.decode([String: PlatformValue].self, forKey: .value)
            self = .map(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .null:
            try container.encode(ValueType.null, forKey: .type)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .unsignedInteger(let value):
            try container.encode(ValueType.unsignedInteger, forKey: .type)
            try container.encode(value, forKey: .value)
        case .float(let value):
            try container.encode(ValueType.float, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bytes(let value):
            try container.encode(ValueType.bytes, forKey: .type)
            try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case .map(let value):
            try container.encode(ValueType.map, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}