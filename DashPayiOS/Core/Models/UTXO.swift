import Foundation
import SwiftData
import SwiftDashCoreSDK

@Model
final class LocalUTXO {
    @Attribute(.unique) var outpoint: String
    var txid: String
    var vout: UInt32
    var address: String
    var script: Data
    var value: UInt64
    var height: UInt32
    var confirmations: UInt32
    var isInstantLocked: Bool
    var isSpent: Bool
    
    init(
        outpoint: String,
        txid: String,
        vout: UInt32,
        address: String,
        script: Data,
        value: UInt64,
        height: UInt32 = 0,
        confirmations: UInt32 = 0,
        isInstantLocked: Bool = false,
        isSpent: Bool = false
    ) {
        self.outpoint = outpoint
        self.txid = txid
        self.vout = vout
        self.address = address
        self.script = script
        self.value = value
        self.height = height
        self.confirmations = confirmations
        self.isInstantLocked = isInstantLocked
        self.isSpent = isSpent
    }
    
    convenience init(from sdkUTXO: SwiftDashCoreSDK.UTXO) {
        self.init(
            outpoint: sdkUTXO.outpoint,
            txid: sdkUTXO.txid,
            vout: sdkUTXO.vout,
            address: sdkUTXO.address,
            script: sdkUTXO.script,
            value: sdkUTXO.value,
            height: sdkUTXO.height,
            confirmations: sdkUTXO.confirmations,
            isInstantLocked: sdkUTXO.isInstantLocked,
            isSpent: false
        )
    }
    
    var displayValue: String {
        let dashAmount = Double(value) / 100_000_000
        return String(format: "%.8g DASH", dashAmount)
    }
    
    var isSpendable: Bool {
        !isSpent && confirmations > 0
    }
}