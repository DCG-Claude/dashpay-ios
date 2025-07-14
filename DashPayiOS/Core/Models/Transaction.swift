import Foundation
import SwiftData
import SwiftDashCoreSDK

@Model
final class Transaction {
    private static let duffsPerDash: Decimal = 100_000_000
    
    @Attribute(.unique) var txid: String
    var height: UInt32?
    var timestamp: Date
    var amount: Int64
    var fee: UInt64?
    var confirmations: UInt32
    var isInstantLocked: Bool
    var raw: Data?
    var size: UInt32?
    var version: UInt32?
    
    init(
        txid: String,
        height: UInt32? = nil,
        timestamp: Date = Date(),
        amount: Int64 = 0,
        fee: UInt64? = nil,
        confirmations: UInt32 = 0,
        isInstantLocked: Bool = false,
        raw: Data? = nil,
        size: UInt32? = nil,
        version: UInt32? = nil
    ) {
        self.txid = txid
        self.height = height
        self.timestamp = timestamp
        self.amount = amount
        self.fee = fee
        self.confirmations = confirmations
        self.isInstantLocked = isInstantLocked
        self.raw = raw
        self.size = size
        self.version = version
    }
    
    var isConfirmed: Bool {
        confirmations > 0
    }
    
    var displayAmount: String {
        let dashAmount = Decimal(abs(amount)) / Self.duffsPerDash
        let sign = amount < 0 ? "-" : ""
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        
        let formattedAmount = formatter.string(from: dashAmount as NSDecimalNumber) ?? "0.00000000"
        return "\(sign)\(formattedAmount) DASH"
    }
    
    var displayStatus: String {
        if isInstantLocked {
            return "InstantSend"
        } else if confirmations > 6 {
            return "Confirmed"
        } else if confirmations > 0 {
            return "\(confirmations) confirmations"
        } else {
            return "Unconfirmed"
        }
    }
    
    convenience init(from sdkTransaction: SwiftDashCoreSDK.Transaction) {
        self.init(
            txid: sdkTransaction.txid,
            height: sdkTransaction.height,
            timestamp: sdkTransaction.timestamp,
            amount: sdkTransaction.amount,
            fee: sdkTransaction.fee,
            confirmations: sdkTransaction.confirmations,
            isInstantLocked: sdkTransaction.isInstantLocked,
            raw: sdkTransaction.raw,
            size: sdkTransaction.size,
            version: sdkTransaction.version
        )
    }
}