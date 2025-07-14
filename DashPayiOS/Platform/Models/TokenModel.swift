import Foundation

// MARK: - Supporting Token Data Structures

struct TokenPriceInfo: Codable {
    let pricingType: String // "SinglePrice" or "SetPrices"
    let singlePrice: UInt64?
    let priceEntries: [TokenPriceEntry]?
    
    var effectivePrice: UInt64? {
        if pricingType == "SinglePrice" {
            return singlePrice
        } else if let entries = priceEntries, !entries.isEmpty {
            return entries.first?.price
        }
        return nil
    }
}

struct TokenPriceEntry: Codable {
    let amount: UInt64
    let price: UInt64
}

struct TokenStatus: Codable {
    let tokenId: String
    let active: Bool
    let paused: Bool
    let emergencyMode: Bool
    
    var isOperational: Bool {
        return active && !paused && !emergencyMode
    }
}

struct TokenClaim: Codable {
    let name: String
    let amount: UInt64
}

struct TokenModel: Identifiable, Codable {
    let id: String // Token ID (Base58)
    let contractId: String // Contract ID (Base58)
    let tokenPosition: UInt16 // Position in contract
    let name: String?
    let symbol: String?
    let decimals: Int?
    let totalSupply: UInt64?
    let balance: UInt64
    let frozenBalance: UInt64?
    let frozen: Bool
    let availableClaims: [TokenClaim]?
    let priceInfo: TokenPriceInfo?
    let status: TokenStatus?
    
    // MARK: - Initialization
    
    init(
        id: String,
        contractId: String,
        tokenPosition: UInt16 = 0,
        name: String? = nil,
        symbol: String? = nil,
        decimals: Int? = nil,
        totalSupply: UInt64? = nil,
        balance: UInt64 = 0,
        frozenBalance: UInt64? = nil,
        frozen: Bool = false,
        availableClaims: [TokenClaim]? = nil,
        priceInfo: TokenPriceInfo? = nil,
        status: TokenStatus? = nil
    ) {
        self.id = id
        self.contractId = contractId
        self.tokenPosition = tokenPosition
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.totalSupply = totalSupply
        self.balance = balance
        self.frozenBalance = frozenBalance
        self.frozen = frozen
        self.availableClaims = availableClaims
        self.priceInfo = priceInfo
        self.status = status
    }
    
    /// Initialize from TokenService data
    init(from tokenInfo: TokenService.TokenInfo, balance: TokenService.TokenBalance) {
        self.id = tokenInfo.tokenId
        self.contractId = tokenInfo.contractId
        self.tokenPosition = tokenInfo.tokenPosition
        self.name = tokenInfo.name
        self.symbol = tokenInfo.symbol
        self.decimals = tokenInfo.decimals
        self.totalSupply = tokenInfo.totalSupply
        self.balance = balance.balance
        self.frozenBalance = nil // Would need separate call to get frozen balance
        self.frozen = balance.frozen
        self.availableClaims = nil // Would need separate call to get claims
        // Convert TokenService.TokenPriceInfo to local TokenPriceInfo
        if let servicePriceInfo = tokenInfo.priceInfo {
            self.priceInfo = TokenPriceInfo(
                pricingType: servicePriceInfo.pricingType,
                singlePrice: servicePriceInfo.singlePrice,
                priceEntries: servicePriceInfo.priceEntries?.map { entry in
                    TokenPriceEntry(amount: entry.amount, price: entry.price)
                }
            )
        } else {
            self.priceInfo = nil
        }
        self.status = nil // Would need separate call to get status
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        return name ?? symbol ?? "Unknown Token"
    }
    
    var displaySymbol: String {
        return symbol ?? "UNK"
    }
    
    var effectiveDecimals: Int {
        return decimals ?? 8 // Default to 8 decimals like most crypto tokens
    }
    
    var formattedBalance: String {
        let divisor = pow(10.0, Double(effectiveDecimals))
        let tokenAmount = Double(balance) / divisor
        return String(format: "%.\(effectiveDecimals)f %@", tokenAmount, displaySymbol)
    }
    
    var formattedFrozenBalance: String {
        guard let frozenBalance = frozenBalance else { return "Unknown" }
        let divisor = pow(10.0, Double(effectiveDecimals))
        let tokenAmount = Double(frozenBalance) / divisor
        return String(format: "%.\(effectiveDecimals)f %@", tokenAmount, displaySymbol)
    }
    
    var formattedTotalSupply: String {
        guard let supply = totalSupply else { return "Unknown" }
        let divisor = pow(10.0, Double(effectiveDecimals))
        let tokenAmount = Double(supply) / divisor
        return String(format: "%.\(effectiveDecimals)f %@", tokenAmount, displaySymbol)
    }
    
    var availableBalance: UInt64 {
        guard let frozenBalance = frozenBalance else { return balance }
        return balance > frozenBalance ? balance - frozenBalance : 0
    }
    
    var formattedAvailableBalance: String {
        let divisor = pow(10.0, Double(effectiveDecimals))
        let tokenAmount = Double(availableBalance) / divisor
        return String(format: "%.\(effectiveDecimals)f %@", tokenAmount, displaySymbol)
    }
    
    var hasClaimsAvailable: Bool {
        return availableClaims?.isEmpty == false
    }
    
    var isPurchasable: Bool {
        return priceInfo?.effectivePrice != nil && status?.isOperational != false
    }
    
    var isTransferable: Bool {
        return !frozen && status?.isOperational != false
    }
    
    var pricePerToken: Double {
        // Convert the price to DASH from credits
        // Assuming the price is in credits, and 1 DASH = 100,000,000 satoshis
        if let effectivePrice = priceInfo?.effectivePrice {
            return Double(effectivePrice) / 100_000_000.0
        }
        return 0.0
    }
}