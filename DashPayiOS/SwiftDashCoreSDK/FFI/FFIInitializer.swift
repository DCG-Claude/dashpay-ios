import Foundation
// DashSPVFFI import removed - unified FFI handles all initialization

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
        // Since the unified FFI library handles all initialization,
        // we don't need to call dash_spv_ffi_init_logging anymore.
        // This method now just returns success immediately.
        
        print("ℹ️ FFI initialization handled by unified library, skipping SPV-specific init")
        print("✅ SPV FFI marked as initialized (unified FFI handles actual initialization)")
        
        // Return success immediately
        return true
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