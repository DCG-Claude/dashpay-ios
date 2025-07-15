import Foundation

/// Utility for formatting Dash amounts consistently across the app
enum DashFormatting {
    
    /// The number of satoshis in one DASH
    static let satoshisPerDash: Double = 100_000_000.0
    
    /// Converts satoshis to DASH amount
    /// - Parameter satoshis: The amount in satoshis
    /// - Returns: The amount in DASH as a Double
    static func satoshisToDash(_ satoshis: UInt64) -> Double {
        return Double(satoshis) / satoshisPerDash
    }
    
    /// Formats a value in satoshis to a human-readable Dash string
    /// - Parameter satoshis: The amount in satoshis (1 DASH = 100,000,000 satoshis)
    /// - Returns: A formatted string with 8 decimal places followed by " DASH"
    static func formatDash(_ satoshis: UInt64) -> String {
        let dash = satoshisToDash(satoshis)
        return String(format: "%.8f DASH", dash)
    }
    
    /// Formats a value in satoshis to a human-readable Dash string without the DASH suffix
    /// - Parameter satoshis: The amount in satoshis (1 DASH = 100,000,000 satoshis)
    /// - Returns: A formatted string with 8 decimal places
    static func formatDashAmount(_ satoshis: UInt64) -> String {
        let dash = satoshisToDash(satoshis)
        return String(format: "%.8f", dash)
    }
}