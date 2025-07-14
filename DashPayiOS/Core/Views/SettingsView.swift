import SwiftUI
import SwiftData
import SwiftDashCoreSDK

// Core types are defined in SwiftDashCoreSDK/Models/
// Using the types from there to avoid duplication

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
                    // Force app restart
                    exit(0)
                }
            } message: {
                Text(resetMessage)
            }
        }
    }
    
    private func resetAllData() {
        do {
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
            
            resetMessage = "All data has been reset. The app will now restart."
            showingResetAlert = true
        } catch {
            resetMessage = "Failed to reset data: \(error.localizedDescription)"
            showingResetAlert = true
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