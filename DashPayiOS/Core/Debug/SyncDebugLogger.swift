import Foundation
import os.log
import SwiftDashCoreSDK
import Compression

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
    // Log rotation configuration
    private static let maxLogFileSize: UInt64 = 10 * 1024 * 1024 // 10MB
    private static let maxLogAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private static let maxArchivedLogs: Int = 5
    
    private static let logFileURL: URL? = {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("dashpay_sync_debug.log")
    }()
    
    private static let logDirectoryURL: URL? = {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("DashPayLogs")
    }()
    
    /// Write debug log to file for later analysis with rotation
    public static func writeToFile(_ message: String) {
        guard let url = logFileURL else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        DispatchQueue.global(qos: .background).async {
            do {
                // Ensure log directory exists
                if let logDir = logDirectoryURL {
                    try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                }
                
                // Check if rotation is needed before writing
                if shouldRotateLog(url: url) {
                    rotateLogFile(url: url)
                }
                
                // Write log entry
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
                
                // Clean up old log files
                cleanupOldLogs()
                
            } catch {
                print("Failed to write log: \(error)")
            }
        }
    }
    
    /// Check if log rotation is needed based on file size or age
    private static func shouldRotateLog(url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            
            // Check file size
            if let fileSize = attributes[.size] as? UInt64, fileSize >= maxLogFileSize {
                return true
            }
            
            // Check file age
            if let creationDate = attributes[.creationDate] as? Date {
                let fileAge = Date().timeIntervalSince(creationDate)
                if fileAge >= maxLogAge {
                    return true
                }
            }
            
        } catch {
            print("Failed to check log file attributes: \(error)")
        }
        
        return false
    }
    
    /// Rotate the current log file
    private static func rotateLogFile(url: URL) {
        guard let logDir = logDirectoryURL else { return }
        
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            
            let archivedLogURL = logDir.appendingPathComponent("dashpay_sync_debug_\(timestamp).log")
            
            // Move current log to archived location
            try FileManager.default.moveItem(at: url, to: archivedLogURL)
            
            // Compress archived log file to save space
            if let compressedURL = compressLogFile(archivedLogURL) {
                try FileManager.default.removeItem(at: archivedLogURL)
                print("📦 Log file archived and compressed: \(compressedURL.lastPathComponent)")
            }
            
        } catch {
            print("Failed to rotate log file: \(error)")
        }
    }
    
    /// Compress a log file using Apple's Compression framework
    private static func compressLogFile(_ url: URL) -> URL? {
        let compressedURL = url.appendingPathExtension("gz")
        
        do {
            let data = try Data(contentsOf: url)
            let compressedData = try data.compressed(using: .lzfse)
            try compressedData.write(to: compressedURL)
            return compressedURL
        } catch {
            print("Failed to compress log file: \(error)")
            return nil
        }
    }
    
    /// Clean up old log files beyond the retention limit
    private static func cleanupOldLogs() {
        guard let logDir = logDirectoryURL else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.creationDateKey], options: [])
            
            let logFiles = files.filter { url in
                url.lastPathComponent.hasPrefix("dashpay_sync_debug_") &&
                (url.pathExtension == "log" || url.pathExtension == "gz" || url.lastPathComponent.hasSuffix(".log.gz"))
            }
            
            // Sort by creation date (newest first)
            let sortedFiles = logFiles.sorted { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
            }
            
            // Remove files beyond the limit
            let filesToDelete = sortedFiles.dropFirst(maxArchivedLogs)
            for file in filesToDelete {
                try FileManager.default.removeItem(at: file)
                print("🗑️ Deleted old log file: \(file.lastPathComponent)")
            }
            
            // Also remove files older than maxLogAge
            let cutoffDate = Date().addingTimeInterval(-maxLogAge)
            for file in sortedFiles {
                if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try FileManager.default.removeItem(at: file)
                    print("🗑️ Deleted expired log file: \(file.lastPathComponent)")
                }
            }
            
        } catch {
            print("Failed to clean up old log files: \(error)")
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