import Foundation
import OSLog

public extension SpeechSession {

    /// Logging levels supported by `SpeechSession`.
    enum LogLevel: CaseIterable, Sendable, Hashable {
        case off
        case error
        case notice
        case info
        case debug

        var rank: Int {
            switch self {
            case .off: return 0
            case .error: return 1
            case .notice: return 2
            case .info: return 3
            case .debug: return 4
            }
        }

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .error: return "Error"
            case .notice: return "Notice"
            case .info: return "Info"
            case .debug: return "Debug"
            }
        }
    }

    /// Global logging level for all `SpeechSession` instances. Defaults to `.off`.
    static var logging: LogLevel = .off

    internal static let logger = Logger(subsystem: "com.auralkit.speech", category: "SpeechSession")

    internal static func shouldLog(_ level: LogLevel) -> Bool {
        if logging == .off { return false }
        return level.rank <= logging.rank
    }
}
