import Foundation
import DashSPVFFI

/// Manages FFI initialization to avoid conflicts between multiple Rust libraries
public class FFIInitializer {
    private static var isInitialized = false
    private static var initializationError: Error?
    private static let queue = DispatchQueue(label: "com.dash.ffi.initializer")
    
    public enum InitializationError: LocalizedError {
        case alreadyInitialized
        case initializationFailed(String)
        case libraryNotFound
        
        public var errorDescription: String? {
            switch self {
            case .alreadyInitialized:
                return "FFI libraries have already been initialized"
            case .initializationFailed(let message):
                return "FFI initialization failed: \(message)"
            case .libraryNotFound:
                return "Required FFI library not found"
            }
        }
    }
    
    /// Initialize FFI libraries with proper error handling
    public static func initialize(logLevel: String = "info") throws {
        try queue.sync {
            // Check if already initialized
            if isInitialized {
                throw InitializationError.alreadyInitialized
            }
            
            // If there was a previous error, throw it
            if let error = initializationError {
                throw error
            }
            
            do {
                // Initialize with timeout protection
                let result = initializeWithTimeout(logLevel: logLevel, timeout: 5.0)
                
                if result {
                    isInitialized = true
                    print("✅ FFI libraries initialized successfully")
                } else {
                    let error = InitializationError.initializationFailed("Initialization timed out")
                    initializationError = error
                    throw error
                }
            } catch {
                initializationError = error
                throw error
            }
        }
    }
    
    /// Initialize with timeout protection
    private static func initializeWithTimeout(logLevel: String, timeout: TimeInterval) -> Bool {
        var initResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)
        
        // Run initialization on a separate queue
        DispatchQueue.global(qos: .userInitiated).async {
            print("🔄 Attempting FFI initialization with log level: \(logLevel)")
            
            // Clear any previous errors first
            dash_spv_ffi_clear_error()
            
            // Try to initialize logging
            // First attempt: direct call
            initResult = logLevel.withCString { logLevelCStr in
                return dash_spv_ffi_init_logging(logLevelCStr)
            }
            
            // Check result
            if initResult != 0 {
                print("🔴 First init attempt failed with code \(initResult)")
                
                // Check for error
                if let errorMsg = dash_spv_ffi_get_last_error() {
                    let error = String(cString: errorMsg)
                    print("🔴 FFI init_logging error: \(error)")
                    dash_spv_ffi_clear_error()
                    
                    // If it says already initialized, that's OK
                    if error.contains("already initialized") || error.contains("logger") {
                        print("ℹ️ FFI logging already initialized, continuing...")
                        initResult = 0  // Consider this a success
                    }
                } else {
                    print("🔴 FFI init_logging failed with code \(initResult) but no error message")
                }
            } else {
                print("✅ FFI logging initialized successfully")
            }
            
            semaphore.signal()
        }
        
        // Wait with timeout
        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        
        if timeoutResult == .timedOut {
            print("⚠️ FFI initialization timed out after \(timeout) seconds")
            return false
        }
        
        print("🔄 FFI initialization result: \(initResult)")
        return initResult == 0
    }
    
    /// Check if FFI libraries are initialized
    public static var initialized: Bool {
        queue.sync { isInitialized }
    }
    
    /// Reset initialization state (for testing only)
    internal static func reset() {
        queue.sync {
            isInitialized = false
            initializationError = nil
        }
    }
    
    /// Initialize with retry logic
    public static func initializeWithRetry(logLevel: String = "info", maxAttempts: Int = 3) throws {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                print("🔄 FFI initialization attempt \(attempt) of \(maxAttempts)")
                try initialize(logLevel: logLevel)
                return
            } catch InitializationError.alreadyInitialized {
                // Already initialized, that's fine
                return
            } catch {
                lastError = error
                print("⚠️ Attempt \(attempt) failed: \(error)")
                
                if attempt < maxAttempts {
                    // Wait before retrying
                    Thread.sleep(forTimeInterval: Double(attempt) * 0.5)
                    reset() // Reset for retry
                }
            }
        }
        
        throw lastError ?? InitializationError.initializationFailed("Unknown error")
    }
}

/// Extension to handle deferred initialization
public extension FFIInitializer {
    /// Initialize FFI libraries when actually needed (lazy initialization)
    static func ensureInitialized(logLevel: String = "info") throws {
        guard !initialized else { return }
        try initialize(logLevel: logLevel)
    }
    
    /// Try to initialize without throwing
    @discardableResult
    static func tryInitialize(logLevel: String = "info") -> Bool {
        do {
            try ensureInitialized(logLevel: logLevel)
            return true
        } catch {
            print("⚠️ FFI initialization failed: \(error)")
            return false
        }
    }
}

/// Configuration for FFI initialization
public struct FFIConfiguration {
    public let logLevel: String
    public let enableMockMode: Bool
    public let initializationTimeout: TimeInterval
    
    public init(
        logLevel: String = "info",
        enableMockMode: Bool = false,
        initializationTimeout: TimeInterval = 5.0
    ) {
        self.logLevel = logLevel
        self.enableMockMode = enableMockMode
        self.initializationTimeout = initializationTimeout
    }
    
    public static let `default` = FFIConfiguration()
    public static let debug = FFIConfiguration(logLevel: "debug")
    
    #if DEBUG
    public static let mock = FFIConfiguration(enableMockMode: true)
    #endif
}

/// Global FFI manager for coordinating library usage
public class FFIManager {
    public static let shared = FFIManager()
    
    private var configuration: FFIConfiguration = .default
    private let queue = DispatchQueue(label: "com.dash.ffi.manager")
    
    private init() {}
    
    /// Configure FFI settings
    public func configure(with configuration: FFIConfiguration) {
        queue.sync {
            self.configuration = configuration
        }
    }
    
    /// Initialize FFI with current configuration
    public func initialize() throws {
        let config = queue.sync { configuration }
        
        #if DEBUG
        if config.enableMockMode {
            print("🎭 FFI running in mock mode - skipping initialization")
            return
        }
        #else
        // Never allow mock mode in production builds
        if config.enableMockMode {
            print("⚠️ Mock mode requested in production build - ignoring and proceeding with real FFI")
        }
        #endif
        
        try FFIInitializer.initializeWithRetry(
            logLevel: config.logLevel,
            maxAttempts: 3
        )
    }
    
    /// Check if running in mock mode
    public var isMockMode: Bool {
        queue.sync { configuration.enableMockMode }
    }
    
    /// Get diagnostic information about FFI state
    public func diagnostics() -> String {
        var info = "FFI Diagnostics:\n"
        info += "- Initialized: \(FFIInitializer.initialized)\n"
        info += "- Mock Mode: \(isMockMode)\n"
        info += "- Log Level: \(configuration.logLevel)\n"
        info += "- Timeout: \(configuration.initializationTimeout)s\n"
        
        // FFIBridge not available - skip error check
        info += "- Last Error: (FFIBridge not available)\n"
        
        return info
    }
}