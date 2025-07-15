import Foundation

enum PlatformNetwork: String, CaseIterable, Codable {
    case mainnet = "mainnet"
    case testnet = "testnet"
    case devnet = "devnet"
    
    var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .devnet:
            return "Devnet"
        }
    }
    
    var sdkNetwork: FFINetwork {
        switch self {
        case .mainnet:
            return FFINetwork(rawValue: 0)
        case .testnet:
            return FFINetwork(rawValue: 1)
        case .devnet:
            return FFINetwork(rawValue: 2)
        }
    }
    
    static var defaultNetwork: PlatformNetwork {
        return .testnet
    }
}