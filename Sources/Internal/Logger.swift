import Foundation

enum LogLevel: Int, Comparable {
    case trace
    case debug
    case info
    case warning
    case error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct Logger {
    let label: String
    private let threshold: LogLevel

    init(label: String, threshold: LogLevel = .info) {
        self.label = label
        self.threshold = threshold
    }

    func trace(_ message: @autoclosure () -> String) {
        log(.trace, message())
    }

    func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    private func log(_ level: LogLevel, _ message: String) {
        guard level >= threshold else { return }
        print("[\(level.name)] [\(label)] \(message)")
    }
}

private extension LogLevel {
    var name: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}
