import Foundation
import SwiftDashSDK

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
    
    var sdkNetwork: DashSDKNetwork {
        switch self {
        case .mainnet:
            return DashSDKNetwork(rawValue: 0) // Mainnet
        case .testnet:
            return DashSDKNetwork(rawValue: 1) // Testnet
        case .devnet:
            return DashSDKNetwork(rawValue: 3) // Local (for devnet)
        }
    }
    
    static var defaultNetwork: PlatformNetwork {
        return .testnet
    }
}