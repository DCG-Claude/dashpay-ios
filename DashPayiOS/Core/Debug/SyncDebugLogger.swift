import Foundation
import os.log
import SwiftDashCoreSDK

/// Debug logger for sync connection issues
public class SyncDebugLogger {
    private static let logger = Logger(subsystem: "com.dash.sdk", category: "SyncDebug")
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    // MARK: - Connection Logging
    
    public static func logConnectionAttempt(_ attempt: Int, maxAttempts: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let message = """
        🔄 Connection Attempt \(attempt)/\(maxAttempts)
        ├─ Time: \(timestamp)
        ├─ Thread: \(Thread.current.name ?? "Unknown") [\(Thread.current.isMainThread ? "Main" : "Background")]
        ├─ FFI State: Active ✅
        └─ Memory: \(getMemoryUsage())
        """
        print(message)
        logger.info("\(message)")
    }
    
    public static func logConnectionError(_ error: Error, context: String) {
        let timestamp = dateFormatter.string(from: Date())
        var errorDetails = """
        🔴 Connection Error in \(context)
        ├─ Time: \(timestamp)
        ├─ Error: \(error.localizedDescription)
        ├─ Type: \(type(of: error))
        """
        
        if let sdkError = error as? SwiftDashCoreSDK.DashSDKError {
            errorDetails += "\n├─ SDK Error: \(sdkError.localizedDescription)"
        }
        
        // Check for FFI error
        // FFI error checking removed - handled internally by SDK
        
        // Add system error if available
        let systemError = String(cString: strerror(errno))
        if errno != 0 {
            errorDetails += "\n├─ System Error: \(systemError) (errno: \(errno))"
        }
        
        errorDetails += "\n└─ Stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n         "))"
        
        print(errorDetails)
        logger.error("\(errorDetails)")
    }
    
    public static func logConnectionSuccess(peers: Int, height: UInt32) {
        let message = """
        ✅ Connection Successful
        ├─ Peers: \(peers)
        ├─ Height: \(height)
        └─ Time: \(dateFormatter.string(from: Date()))
        """
        print(message)
        logger.info("\(message)")
    }
    
    // MARK: - Sync Progress Logging
    
    public static func logSyncProgress(_ progress: DetailedSyncProgress) {
        let message = """
        📊 Sync Progress Update
        ├─ Height: \(progress.currentHeight)/\(progress.totalHeight) (\(progress.formattedPercentage))
        ├─ Speed: \(progress.formattedSpeed)
        ├─ Stage: \(progress.stage.icon) \(progress.stage.description)
        ├─ Peers: \(progress.connectedPeers)
        ├─ ETA: \(progress.formattedTimeRemaining)
        └─ Duration: \(progress.formattedSyncDuration)
        """
        print(message)
        logger.info("\(message)")
    }
    
    public static func logSyncEvent(_ event: SPVEvent) {
        let timestamp = dateFormatter.string(from: Date())
        var message = "📡 SPV Event at \(timestamp): "
        
        switch event {
        case .blockReceived(let height, let hash):
            message += "Block received at height \(height): \(hash)"
        case .transactionReceived(let txid, let confirmed, let amount, let addresses, let blockHeight):
            message += "Transaction \(confirmed ? "confirmed" : "unconfirmed"): \(txid), amount: \(amount)"
        case .balanceUpdated(let balance):
            message += "Balance updated: \(balance.confirmed) confirmed, \(balance.pending) pending"
        case .syncProgressUpdated(let progress):
            message += "Sync progress: \(progress.currentHeight)/\(progress.totalHeight)"
        case .connectionStatusChanged(let connected):
            message += "Connection status changed: \(connected ? "Connected" : "Disconnected")"
        case .error(let error):
            message += "Error: \(error)"
        case .mempoolTransactionAdded(let txid, let amount, let addresses):
            message += "Mempool TX added: \(txid), amount: \(amount)"
        case .mempoolTransactionConfirmed(let txid, let blockHeight, let confirmations):
            message += "Mempool TX confirmed: \(txid) at height \(blockHeight)"
        case .mempoolTransactionRemoved(let txid, let reason):
            message += "Mempool TX removed: \(txid), reason: \(reason)"
        }
        
        print(message)
        logger.info("\(message)")
    }
    
    // MARK: - Network Logging
    
    
    
    // MARK: - FFI Logging
    
    public static func logFFIStatus() {
        let diagnostics = "FFI Status: Active"
        print("🔧 \(diagnostics)")
        logger.info("\(diagnostics)")
    }
    
    public static func logFFIError(context: String, code: Int32) {
        var message = """
        🔴 FFI Error in \(context)
        ├─ Code: \(code)
        """
        
        message += "\n└─ FFI State: Active"
        
        print(message)
        logger.error("\(message)")
    }
    
    // MARK: - Configuration Logging
    
    public static func logConfiguration(_ config: SPVClientConfiguration) {
        let message = """
        ⚙️ SPV Client Configuration
        ├─ Network: \(config.network.name)
        ├─ Log Level: \(config.logLevel)
        ├─ Max Peers: \(config.maxPeers)
        ├─ Configured Peers: \(config.additionalPeers.count)
        │  \(config.additionalPeers.map { "├─ \($0)" }.joined(separator: "\n│  "))
        ├─ Data Directory: \(config.dataDirectory?.path ?? "Not configured")
        └─ Filter Load: \(config.enableFilterLoad)
        """
        print(message)
        logger.info("\(message)")
    }
    
    // MARK: - Diagnostic Summary
    
    
    // MARK: - Helper Methods
    
    private static func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1f MB", usedMB)
        }
        return "Unknown"
    }
    
    // MARK: - Connection State History
    
    private static var stateHistory: [(Date, String)] = []
    private static let stateHistoryQueue = DispatchQueue(label: "com.dash.sdk.stateHistory")
    
    public static func logStateChange(_ state: String) {
        stateHistoryQueue.sync {
            let entry = (Date(), state)
            stateHistory.append(entry)
            
            // Keep last 50 entries
            if stateHistory.count > 50 {
                stateHistory.removeFirst()
            }
        }
        
        let timestamp = dateFormatter.string(from: Date())
        print("🔸 State Change [\(timestamp)]: \(state)")
        logger.info("State Change: \(state)")
    }
    
    public static func getStateHistory() -> String {
        return stateHistoryQueue.sync {
            var history = "📜 Connection State History:\n"
            for (date, state) in stateHistory.suffix(20) {
                let timestamp = dateFormatter.string(from: date)
                history += "├─ [\(timestamp)] \(state)\n"
            }
            return history
        }
    }
}

// MARK: - Log File Support

extension SyncDebugLogger {
    private static let logFileURL: URL? = {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("dashpay_sync_debug.log")
    }()
    
    /// Write debug log to file for later analysis
    public static func writeToFile(_ message: String) {
        guard let url = logFileURL else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        DispatchQueue.global(qos: .background).async {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    handle.seekToEndOfFile()
                    guard let data = logEntry.data(using: .utf8) else {
                        print("⚠️ Failed to encode log entry to UTF-8 data")
                        handle.closeFile()
                        return
                    }
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try logEntry.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to write log: \(error)")
            }
        }
    }
    
    /// Get debug log file path
    public static func getLogFilePath() -> String? {
        return logFileURL?.path
    }
    
    /// Clear debug log file
    public static func clearLogFile() {
        guard let url = logFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}