import SwiftUI

struct SendTransactionView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    
    let account: HDAccount
    
    @State private var recipientAddress = ""
    @State private var amountString = ""
    @State private var feeRate: UInt64 = 1000
    @State private var estimatedFee: UInt64 = 0
    @State private var isSending = false
    @State private var errorMessage = ""
    @State private var successTxid = ""
    @State private var isValidAddress = true
    
    private var amount: UInt64? {
        return convertDashToSatoshis(amountString)
    }
    
    /// Converts a Dash amount string to satoshis using integer-only arithmetic to avoid floating-point precision errors
    private func convertDashToSatoshis(_ dashString: String) -> UInt64? {
        let trimmed = dashString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let components = trimmed.components(separatedBy: ".")
        guard components.count <= 2 else { return nil } // Invalid format with multiple decimal points
        
        let wholePart = components[0]
        let fractionalPart = components.count == 2 ? components[1] : ""
        
        // Validate that both parts contain only digits
        guard wholePart.allSatisfy(\.isNumber),
              fractionalPart.allSatisfy(\.isNumber) else { return nil }
        
        // Convert whole part to satoshis
        guard let wholeNumber = UInt64(wholePart) else { return nil }
        guard wholeNumber <= UInt64.max / 100_000_000 else { return nil } // Overflow check
        let wholeSatoshis = wholeNumber * 100_000_000
        
        // Convert fractional part to satoshis (pad or truncate to 8 decimal places)
        var fractionalSatoshis: UInt64 = 0
        if !fractionalPart.isEmpty {
            let paddedFractional = fractionalPart.padding(toLength: 8, withPad: "0", startingAt: 0)
            let truncatedFractional = String(paddedFractional.prefix(8))
            guard let fractionalNumber = UInt64(truncatedFractional) else { return nil }
            fractionalSatoshis = fractionalNumber
        }
        
        // Check for overflow when adding whole and fractional parts
        guard wholeSatoshis <= UInt64.max - fractionalSatoshis else { return nil }
        
        return wholeSatoshis + fractionalSatoshis
    }
    
    private var availableBalance: UInt64 {
        account.balance?.total ?? 0
    }
    
    private var totalAmount: UInt64 {
        (amount ?? 0) + estimatedFee
    }
    
    private var isValid: Bool {
        guard let amount = amount, amount > 0 else { return false }
        return !recipientAddress.isEmpty &&
               totalAmount <= availableBalance &&
               isValidAddress
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Balance Section
                Section {
                    HStack {
                        Text("Available Balance")
                        Spacer()
                        Text(DashFormatting.formatDash(availableBalance))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }
                
                // Recipient Section
                Section("Recipient") {
                    VStack(alignment: .leading) {
                        TextField("Dash Address", text: $recipientAddress)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .onChange(of: recipientAddress) { _ in
                                validateAddress()
                            }
                        
                        if !recipientAddress.isEmpty && !self.isValidAddress {
                            Label("Invalid Dash address", systemImage: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                // Amount Section
                Section("Amount") {
                    HStack {
                        TextField("0.00000000", text: $amountString)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: amountString) { _ in
                                updateEstimatedFee()
                            }
                        
                        Text("DASH")
                            .foregroundColor(.secondary)
                        
                        Button("Max") {
                            setMaxAmount()
                        }
                        #if os(iOS)
                        .buttonStyle(.borderless)
                        #else
                        .buttonStyle(.link)
                        #endif
                    }
                    
                    if let amount = amount {
                        HStack {
                            Text("Amount in satoshis")
                            Spacer()
                            Text("\(amount)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                
                // Fee Section
                Section("Network Fee") {
                    Picker("Fee Rate", selection: $feeRate) {
                        Text("Slow (500 sat/KB)").tag(UInt64(500))
                        Text("Normal (1000 sat/KB)").tag(UInt64(1000))
                        Text("Fast (2000 sat/KB)").tag(UInt64(2000))
                    }
                    .onChange(of: feeRate) {
                        updateEstimatedFee()
                    }
                    
                    HStack {
                        Text("Estimated Fee")
                        Spacer()
                        Text(DashFormatting.formatDash(estimatedFee))
                            .monospacedDigit()
                    }
                }
                
                // Summary Section
                Section("Summary") {
                    HStack {
                        Text("Total")
                            .fontWeight(.medium)
                        Spacer()
                        Text(DashFormatting.formatDash(totalAmount))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    
                    if totalAmount > availableBalance {
                        Label("Insufficient balance", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                // Error/Success Messages
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                if !successTxid.isEmpty {
                    Section("Transaction Sent") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Transaction broadcast successfully", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            
                            HStack {
                                Text("Transaction ID:")
                                    .font(.caption)
                                Text(successTxid)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send Dash")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendTransaction()
                    }
                    .disabled(!isValid || isSending)
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 600)
        #endif
    }
    
    private func validateAddress() {
        if recipientAddress.isEmpty {
            isValidAddress = true
            errorMessage = ""
        } else {
            // Safely unwrap activeWallet
            guard let activeWallet = walletService.activeWallet else {
                isValidAddress = false
                errorMessage = "Wallet not available for address validation"
                return
            }
            let network = activeWallet.network
            
            // Use comprehensive validation that includes length and character checks
            isValidAddress = HDWalletService.isValidAddress(recipientAddress, network: network)
            errorMessage = ""
        }
    }
    
    private func updateEstimatedFee() {
        guard let amount = amount, amount > 0 else {
            estimatedFee = 0
            return
        }
        
        Task {
            do {
                // Mock fee estimation - would use sdk?.estimateFee in production
                estimatedFee = UInt64(Double(amount) * 0.0001) // 0.01% fee
            } catch {
                estimatedFee = 0
                print("Failed to estimate fee: \(error)")
            }
        }
    }
    
    private func setMaxAmount() {
        // Calculate max amount (balance - estimated fee)
        let maxAmount = availableBalance > estimatedFee ? availableBalance - estimatedFee : 0
        
        // Use Decimal arithmetic to preserve precision when converting from satoshis to DASH
        let satoshisDecimal = Decimal(maxAmount)
        let satoshisPerDashDecimal = Decimal(100_000_000)
        let dashDecimal = satoshisDecimal / satoshisPerDashDecimal
        
        // Format with 8 decimal places
        let dashNumber = NSDecimalNumber(decimal: dashDecimal)
        amountString = String(format: "%.8f", dashNumber.doubleValue)
    }
    
    private func sendTransaction() {
        guard let amount = amount, isValid else { return }
        
        isSending = true
        errorMessage = ""
        
        Task {
            do {
                guard let sdk = walletService.sdk else {
                    throw WalletError.notConnected
                }
                
                // Mock transaction - would use sdk.sendTransaction in production
                let txid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                
                successTxid = txid
                
                // Clear form after success
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    dismiss()
                }
                
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isSending = false
        }
    }
    
}