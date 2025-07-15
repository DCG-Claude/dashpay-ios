import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveAddressView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    
    let account: HDAccount
    @State private var currentAddress: HDWatchedAddress?
    @State private var isCopied = false
    @State private var showNewAddressConfirm = false
    @State private var addressGenerationError: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let address = currentAddress ?? account.receiveAddress {
                    // QR Code
                    QRCodeView(content: address.address)
                        .frame(width: 200, height: 200)
                        .cornerRadius(12)
                    
                    // Address Display
                    VStack(spacing: 12) {
                        Text("Your Dash Address")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(address.address)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Button(action: copyAddress) {
                                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(isCopied ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Derivation Path
                        Text(address.derivationPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                    
                    // Address Info
                    VStack(spacing: 8) {
                        if address.transactionIds.isEmpty {
                            Label("Unused address", systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label("\(address.transactionIds.count) transactions", systemImage: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if let balance = address.balance {
                            Text("Balance: \(balance.formattedTotal)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                    
                    Spacer()
                    
                    // Generate New Address Button
                    Button("Generate New Address") {
                        showNewAddressConfirm = true
                    }
                    .disabled(address.transactionIds.isEmpty)
                    
                } else {
                    // No address available
                    VStack(spacing: 20) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No receive address available")
                            .font(.title3)
                        
                        Button("Generate Address") {
                            generateNewAddress()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .navigationTitle("Receive Dash")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 600)
        #endif
        .alert("Generate New Address", isPresented: $showNewAddressConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Generate") {
                generateNewAddress()
            }
        } message: {
            Text("The current address has been used. Generate a new address for better privacy?")
        }
        .alert("Address Generation Error", isPresented: .constant(addressGenerationError != nil)) {
            Button("OK") {
                addressGenerationError = nil
            }
        } message: {
            Text(addressGenerationError ?? "")
        }
    }
    
    private func copyAddress() {
        guard let address = currentAddress ?? account.receiveAddress else { return }
        
        Clipboard.copy(address.address)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func generateNewAddress() {
        do {
            let newAddress = try walletService.generateNewAddress(for: account, isChange: false)
            currentAddress = newAddress
            addressGenerationError = nil // Clear any previous error
        } catch {
            addressGenerationError = "Failed to generate new address: \(error.localizedDescription)"
        }
    }
}

// MARK: - QR Code View

struct QRCodeView: View {
    let content: String
    
    #if os(iOS)
    @State private var qrImage: UIImage?
    #elseif os(macOS)
    @State private var qrImage: NSImage?
    #endif
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        VStack {
            if let image = qrImage {
                #if os(iOS)
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                #elseif os(macOS)
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                #endif
            } else if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text("Failed to generate QR code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        retryQRCodeGeneration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if isLoading {
                ProgressView()
            }
        }
        .onAppear {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        // Reset state
        DispatchQueue.main.async {
            self.isLoading = true
            self.hasError = false
            self.qrImage = nil
        }
        
        // Move QR code generation to background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            
            filter.message = Data(content.utf8)
            filter.correctionLevel = "M"
            
            guard let outputImage = filter.outputImage else {
                // Handle QR filter failure
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.hasError = true
                }
                return
            }
            
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                // Handle CGImage creation failure
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.hasError = true
                }
                return
            }
            
            // Update UI on main thread with successful result
            DispatchQueue.main.async {
                #if os(iOS)
                self.qrImage = UIImage(cgImage: cgImage)
                #elseif os(macOS)
                self.qrImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
                #endif
                self.isLoading = false
                self.hasError = false
            }
        }
    }
    
    private func retryQRCodeGeneration() {
        generateQRCode()
    }
}