import SwiftUI
import SwiftData
import SwiftDashSDK
import SwiftDashCoreSDK

/// Block explorer configuration for different networks
/// This provides configurable base URLs for block explorers across different Dash networks
struct BlockExplorerConfig {
    static func url(for network: DashNetwork, txid: String) -> URL? {
        let baseURL: String
        
        switch network {
        case .mainnet:
            baseURL = "https://insight.dash.org/insight/tx/"
        case .testnet:
            baseURL = "https://testnet-insight.dashevo.org/insight/tx/"
        case .devnet:
            baseURL = "https://insight-testnet.dash.org/insight/tx/"
        case .regtest:
            baseURL = "https://insight-testnet.dash.org/insight/tx/"
        @unknown default:
            baseURL = "https://insight.dash.org/insight/tx/"
        }
        
        return URL(string: "\(baseURL)\(txid)")
    }
}

struct TransactionDetailView: View {
    let transaction: DashPay.Transaction
    @State private var showRawData = false
    @State private var isCopied = false
    @Environment(\.dismiss) private var dismiss
    
    // Access the current network from the app state
    // This can be injected or passed as a parameter when creating the view
    let currentNetwork: DashNetwork
    
    init(transaction: Transaction, currentNetwork: DashNetwork = .testnet) {
        self.transaction = transaction
        self.currentNetwork = currentNetwork
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Transaction Status Header
                    // TODO: Convert local Transaction to SwiftDashCoreSDK.Transaction
                    // For now, show basic info
                    VStack {
                        HStack {
                            Image(systemName: transaction.isInstantLocked ? "lock.fill" : "clock")
                                .foregroundColor(transaction.isInstantLocked ? .green : .orange)
                            Text(transaction.isInstantLocked ? "Instant Locked" : "Pending")
                                .font(.headline)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        
                        VStack(spacing: 10) {
                            Text(transaction.amount > 0 ? "Received" : "Sent")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(DashFormatting.formatDash(UInt64(abs(transaction.amount))))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(transaction.amount > 0 ? .green : .red)
                            
                            Text("DASH")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    // Transaction Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transaction ID:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(transaction.txid)
                            .font(.body)
                            .textSelection(.enabled)
                        
                        Text("Created:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(transaction.timestamp.formatted())
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Technical Information (simplified)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Block Height:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(transaction.height ?? 0)")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Actions
                    VStack(spacing: 12) {
                        Button(action: {
                            Clipboard.copy(transaction.txid)
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                isCopied = false
                            }
                        }) {
                            HStack {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied!" : "Copy Transaction ID")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Transaction Status Header

struct TransactionStatusHeader: View {
    let transaction: SwiftDashCoreSDK.Transaction
    
    var body: some View {
        VStack(spacing: 12) {
            // Direction Icon
            Image(systemName: transaction.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
            
            // Status
            VStack(spacing: 4) {
                if transaction.isInstantLocked {
                    Label("InstantSend Confirmed", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                } else if transaction.confirmations > 0 {
                    Text("\(transaction.confirmations) Confirmations")
                        .font(.headline)
                        .foregroundColor(.green)
                } else {
                    Text("Pending")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                
                Text(transaction.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Transaction Amount Section

struct TransactionAmountSection: View {
    let transaction: SwiftDashCoreSDK.Transaction
    
    var body: some View {
        VStack(spacing: 16) {
            Text(transaction.amount >= 0 ? "Received" : "Sent")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(formatAmount(transaction.amount))
                .font(.system(size: 36, weight: .medium, design: .monospaced))
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
            
            if transaction.fee > 0 {
                VStack(spacing: 4) {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatFee(transaction.fee))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatAmount(_ satoshis: Int64) -> String {
        return DashFormatting.formatDash(UInt64(abs(satoshis)))
    }
    
    private func formatFee(_ satoshis: UInt64) -> String {
        return DashFormatting.formatDash(satoshis)
    }
}

// MARK: - Transaction Details Section

struct TransactionDetailsSection: View {
    let transaction: SwiftDashCoreSDK.Transaction
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Details")
            
            VStack(spacing: 0) {
                TransactionDetailRow(label: "Transaction ID", value: transaction.txid, isMono: true)
                
                if let height = transaction.height {
                    TransactionDetailRow(label: "Block Height", value: "\(height)")
                } else {
                    TransactionDetailRow(label: "Block Height", value: "Unconfirmed")
                }
                
                TransactionDetailRow(label: "Timestamp", value: formatTimestamp(transaction.timestamp))
                TransactionDetailRow(label: "Size", value: "\(transaction.size) bytes")
                TransactionDetailRow(label: "Version", value: "\(transaction.version)")
                
                if let address = transaction.watchedAddress?.address {
                    TransactionDetailRow(label: "Address", value: address, isMono: true)
                }
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        return Self.timestampFormatter.string(from: date)
    }
}

// MARK: - Transaction Technical Section

struct TransactionTechnicalSection: View {
    let transaction: SwiftDashCoreSDK.Transaction
    @Binding var showRawData: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Technical Information")
            
            VStack(spacing: 0) {
                TransactionDetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
                TransactionDetailRow(label: "InstantSend", value: transaction.isInstantLocked ? "Yes" : "No")
                
                // Raw Data Toggle
                HStack {
                    Text("Raw Transaction Data")
                        .font(.body)
                    Spacer()
                    Button(showRawData ? "Hide" : "Show") {
                        withAnimation {
                            showRawData.toggle()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                if showRawData {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(transaction.raw.isEmpty ? "No raw data available" : transaction.raw.hexEncodedString())
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .background(Color(.systemGray5))
                }
            }
        }
    }
}

// MARK: - Transaction Actions Section

struct TransactionActionsSection: View {
    let transaction: SwiftDashCoreSDK.Transaction
    @Binding var isCopied: Bool
    let currentNetwork: DashNetwork
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: copyTransactionId) {
                HStack {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(isCopied ? "Copied!" : "Copy Transaction ID")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)
            }
            
            if let height = transaction.height {
                Button(action: openBlockExplorer) {
                    HStack {
                        Image(systemName: "safari")
                        Text("View in Block Explorer")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func copyTransactionId() {
        Clipboard.copy(transaction.txid)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func openBlockExplorer() {
        // Open transaction in block explorer using configurable URL
        if let url = BlockExplorerConfig.url(for: currentNetwork, txid: transaction.txid) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
    }
}

struct TransactionDetailRow: View {
    let label: String
    let value: String
    let isMono: Bool
    
    init(label: String, value: String, isMono: Bool = false) {
        self.label = label
        self.value = value
        self.isMono = isMono
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(isMono ? .system(.body, design: .monospaced) : .body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        
        Divider()
            .padding(.leading, 16)
    }
}

// MARK: - Data Extension

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}


#Preview {
    // Create a mock transaction for preview
    // Note: In a real app, this would come from SwiftData with proper relationships
    let transaction = Transaction(
        txid: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        height: 850000,
        timestamp: Date(),
        amount: 100000000, // 1 DASH
        fee: 1000,
        confirmations: 6,
        isInstantLocked: true,
        raw: Data(),
        size: 250,
        version: 1
    )
    
    TransactionDetailView(transaction: transaction, currentNetwork: .testnet)
}