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
        guard let dash = Double(amountString) else { return nil }
        return UInt64(dash * 100_000_000)
    }
    
    private var availableBalance: UInt64 {
        account.balance?.total ?? 0
    }
    
    private var totalAmount: UInt64 {
        (amount ?? 0) + estimatedFee
    }
    
    private var isValid: Bool {
        !recipientAddress.isEmpty &&
        amount != nil &&
        amount! > 0 &&
        totalAmount <= availableBalance &&
        // Basic validation - would use sdk?.validateAddress in production
        recipientAddress.starts(with: "X") || recipientAddress.starts(with: "y")
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
                    .onChange(of: feeRate) { _ in
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
        // Basic validation - would use sdk?.validateAddress in production
        if recipientAddress.isEmpty {
            isValidAddress = true
        } else {
            isValidAddress = recipientAddress.starts(with: "X") || recipientAddress.starts(with: "y")
        }
        errorMessage = ""
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
        let dash = Double(maxAmount) / 100_000_000.0
        amountString = String(format: "%.8f", dash)
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