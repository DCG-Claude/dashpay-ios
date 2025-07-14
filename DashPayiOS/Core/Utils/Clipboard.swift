import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }
    
    static func paste() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }
}

struct CopyButton: View {
    let text: String
    let label: String
    @State private var copied = false
    
    init(_ text: String, label: String = "Copy") {
        self.text = text
        self.label = label
    }
    
    var body: some View {
        Button(action: {
            Clipboard.copy(text)
            copied = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        }) {
            Label(copied ? "Copied!" : label, systemImage: copied ? "checkmark.circle" : "doc.on.doc")
        }
        .foregroundColor(copied ? .green : .accentColor)
        #if os(iOS)
        .buttonStyle(.bordered)
        #endif
    }
}

// MARK: - Dash Formatting Utilities

/// Utility for formatting Dash amounts consistently across the app
enum DashFormatting {
    
    /// Formats a value in satoshis to a human-readable Dash string
    /// - Parameter satoshis: The amount in satoshis (1 DASH = 100,000,000 satoshis)
    /// - Returns: A formatted string with 8 decimal places followed by " DASH"
    static func formatDash(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f DASH", dash)
    }
    
    /// Formats a value in satoshis to a human-readable Dash string without the DASH suffix
    /// - Parameter satoshis: The amount in satoshis (1 DASH = 100,000,000 satoshis)
    /// - Returns: A formatted string with 8 decimal places
    static func formatDashAmount(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f", dash)
    }
}