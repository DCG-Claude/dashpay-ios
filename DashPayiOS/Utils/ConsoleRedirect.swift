import Foundation

/// Redirects stdout and stderr to a file for debugging
class ConsoleRedirect {
    private var outputFile: FileHandle?
    private var errorFile: FileHandle?
    private let logURL: URL
    
    init() {
        // Create log file in documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                     in: .userDomainMask).first!
        logURL = documentsPath.appendingPathComponent("dashpay_console.log")
        
        // Remove old log file
        try? FileManager.default.removeItem(at: logURL)
        
        // Create new log file
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
    }
    
    func start() {
        guard let fileHandle = FileHandle(forWritingAtPath: logURL.path) else { return }
        
        // Save original stdout/stderr
        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)
        
        // Redirect to file
        freopen(logURL.path, "a", stdout)
        freopen(logURL.path, "a", stderr)
        
        // Also print to original console
        outputFile = FileHandle(fileDescriptor: originalStdout)
        errorFile = FileHandle(fileDescriptor: originalStderr)
        
        print("=== Console output redirected to: \(logURL.path) ===")
        print("=== App started at: \(Date()) ===\n")
    }
    
    func getLogContents() -> String {
        return (try? String(contentsOf: logURL)) ?? "No logs available"
    }
    
    func getLogURL() -> URL {
        return logURL
    }
}