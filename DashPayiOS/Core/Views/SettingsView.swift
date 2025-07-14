import SwiftUI
import SwiftData
import SwiftDashCoreSDK

// Core types are defined in SwiftDashCoreSDK/Models/
// Using the types from there to avoid duplication

extension Notification.Name {
    static let appShouldReset = Notification.Name("appShouldReset")
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var walletService = WalletService.shared
    @State private var showingResetConfirmation = false
    @State private var showingResetAlert = false
    @State private var resetMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Data Management") {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2024.1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Reset All Data",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all wallets, transactions, and settings. This action cannot be undone.")
            }
            .alert("Reset Complete", isPresented: $showingResetAlert) {
                Button("OK") {
                    // Reset app state gracefully
                    resetAppState()
                }
            } message: {
                Text(resetMessage)
            }
        }
    }
    
    private func resetAllData() {
        Task {
            do {
                // Perform heavy I/O operations on background thread
                let result = try await Task.detached {
                    // Delete all SwiftData models
                    try modelContext.delete(model: HDWallet.self)
                    try modelContext.delete(model: HDAccount.self)
                    try modelContext.delete(model: HDWatchedAddress.self)
                    // Platform models
                    try modelContext.delete(model: PersistentIdentity.self)
                    try modelContext.delete(model: PersistentContract.self)
                    try modelContext.delete(model: PersistentDocument.self)
                    try modelContext.delete(model: PersistentTokenBalance.self)
                    
                    // Save the context
                    try modelContext.save()
                    
                    // Clean up the persistent store
                    ModelContainerHelper.cleanupCorruptStore()
                    
                    return "All data has been reset. The app will now restart."
                }.value
                
                // Update UI on main thread
                await MainActor.run {
                    resetMessage = result
                    showingResetAlert = true
                }
            } catch {
                // Handle errors and update UI on main thread
                await MainActor.run {
                    resetMessage = "Failed to reset data: \(error.localizedDescription)"
                    showingResetAlert = true
                }
            }
        }
    }
    
    private func resetAppState() {
        // Reset the wallet service state
        Task {
            await walletService.disconnect()
            
            // Reset user defaults
            UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
            UserDefaults.standard.removeObject(forKey: "useLocalPeers")
            
            // Return to main app initialization state
            await MainActor.run {
                // Dismiss the settings view
                dismiss()
                
                // Post notification to reset app state
                NotificationCenter.default.post(name: .appShouldReset, object: nil)
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            PersistentIdentity.self,
            PersistentContract.self,
            PersistentDocument.self,
            PersistentTokenBalance.self
        ])
}