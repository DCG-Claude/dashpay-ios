import Foundation

class DebugLogger {
    static let shared = DebugLogger()
    
    private let logFile: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                     in: .userDomainMask).first!
        logFile = documentsPath.appendingPathComponent("debug_connection.log")
        
        // Clear old log
        try? FileManager.default.removeItem(at: logFile)
        
        // Create new log
        FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil)
        
        log("=== Debug Logger Started ===")
        log("Time: \(Date())")
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), 
                                                     dateStyle: .none, 
                                                     timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let data = logMessage.data(using: .utf8),
           let fileHandle = FileHandle(forWritingAtPath: logFile.path) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
        
        // Also print to console
        print(logMessage)
    }
    
    func getLogContents() -> String {
        return (try? String(contentsOf: logFile)) ?? "No logs available"
    }
    
    func getLogPath() -> String {
        return logFile.path
    }
}