import Foundation

/// Logging levels for AudioService
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Minimal logger for AudioService
/// - Note: Quick fix implementation - full logging system planned for v3.2
struct Logger {
    let category: String
    
    // MARK: - Configuration
    
    /// Minimum log level to display (debug builds show all, release shows warning+)
    #if DEBUG
    private static let minLevel: LogLevel = .debug
    #else
    private static let minLevel: LogLevel = .warning
    #endif
    
    // MARK: - Initialization
    
    init(category: String) {
        self.category = category
    }
    
    // MARK: - Logging Methods
    
    func debug(_ message: String, function: String = #function, line: Int = #line) {
        log(.debug, message, function: function, line: line)
    }
    
    func info(_ message: String, function: String = #function, line: Int = #line) {
        log(.info, message, function: function, line: line)
    }
    
    func warning(_ message: String, function: String = #function, line: Int = #line) {
        log(.warning, message, function: function, line: line)
    }
    
    func error(_ message: String, function: String = #function, line: Int = #line) {
        log(.error, message, function: function, line: line)
    }
    
    // MARK: - Core Logging
    
    private func log(_ level: LogLevel, _ message: String, function: String, line: Int) {
        guard level >= Self.minLevel else { return }
        
        let timestamp = Self.timestamp()
        let location = "[\(category)] \(function):\(line)"
        let logMessage = "\(level.emoji) [\(timestamp)] \(location) - \(message)"
        
        // Production: Only print
        // TODO v3.2: Add OSLog, file logging, structured logging
        print(logMessage)
    }
    
    // MARK: - State Transition Assertions
    
    /// Assert state transition success in debug builds
    /// - Parameters:
    ///   - success: Whether transition succeeded
    ///   - from: Source state
    ///   - to: Target state
    ///   - function: Calling function
    ///   - line: Line number
    func assertTransition(
        _ success: Bool,
        from: String,
        to: String,
        function: String = #function,
        line: Int = #line
    ) {
        if !success {
            let message = "State transition failed: \(from) → \(to)"
            error(message, function: function, line: line)
            
            #if DEBUG
            assertionFailure(message)
            #endif
        }
    }
    
    // MARK: - Helpers
    
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

// MARK: - Category Constants

extension Logger {
    static let audio = Logger(category: "AudioService")
    static let engine = Logger(category: "AudioEngine")
    static let playlist = Logger(category: "Playlist")
    static let state = Logger(category: "StateMachine")
    static let session = Logger(category: "AudioSession")
}
