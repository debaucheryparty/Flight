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
            "Invalid voice endpoint: \(endpoint)"
        case let .webSocketClosed(code, reason):
            "WebSocket closed with code \(code) reason: \(reason ?? "none")"
        case let .handshakeFailed(reason):
            "Handshake failed: \(reason)"
        case .connectionTimeout:
            "Connection timed out"
        case .heartbeatTimeout:
            "Heartbeat acknowledged timeout (zombie connection)"
        case .sessionExpired:
            "Session expired"
        case .authenticationFailed:
            "Authentication failed"
        case .invalidPayload:
            "Received invalid payload from Discord"
        case .reconnectFailed:
            "Failed to reconnect after maximum attempts"
        case .missingCredentials:
            "Missing session credentials (sessionID, token, or endpoint)"
        case let .encryptionFailed(reason):
            "Encryption failed: \(reason)"
        case let .opusError(code, reason):
            "Opus error \(code): \(reason)"
        case let .daveError(reason):
            "DAVE error: \(reason)"
        }
    }

    public var errorDescription: String? {
        description
    }
}
