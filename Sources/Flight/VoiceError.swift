import Foundation

public enum VoiceError: Error, CustomStringConvertible, LocalizedError, Equatable {
    case invalidEndpoint(String)
    case webSocketClosed(UInt16, String?)
    case handshakeFailed(String)
    case connectionTimeout
    case heartbeatTimeout
    case sessionExpired
    case authenticationFailed
    case invalidPayload
    case reconnectFailed
    case missingCredentials
    case encryptionFailed(String)
    case opusError(Int32, String)
    case daveError(String)

    public var description: String {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid voice endpoint: \(endpoint)"
        case let .webSocketClosed(code, reason):
            return "WebSocket closed with code \(code) reason: \(reason ?? "none")"
        case let .handshakeFailed(reason):
            return "Handshake failed: \(reason)"
        case .connectionTimeout:
            return "Connection timed out"
        case .heartbeatTimeout:
            return "Heartbeat acknowledged timeout (zombie connection)"
        case .sessionExpired:
            return "Session expired"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidPayload:
            return "Received invalid payload from Discord"
        case .reconnectFailed:
            return "Failed to reconnect after maximum attempts"
        case .missingCredentials:
            return "Missing session credentials (sessionID, token, or endpoint)"
        case let .encryptionFailed(reason):
            return "Encryption failed: \(reason)"
        case let .opusError(code, reason):
            return "Opus error \(code): \(reason)"
        case let .daveError(reason):
            return "DAVE error: \(reason)"
        }
    }

    public var errorDescription: String? {
        return description
    }
}
