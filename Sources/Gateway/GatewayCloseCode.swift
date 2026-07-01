import Foundation

enum GatewayCloseCode: UInt16, Codable, CustomStringConvertible {
    case normalClosure = 1000
    case abnormalClosure = 1006
    case unknownOpcode = 4001
    case failedToDecode = 4002
    case notAuthenticated = 4003
    case authenticationFailed = 4004
    case alreadyAuthenticated = 4005
    case sessionNoLongerValid = 4006
    case sessionTimeout = 4009
    case serverNotFound = 4011
    case unknownProtocol = 4012
    case disconnected = 4014
    case voiceServerCrashed = 4015
    case unknownEncryptionMode = 4016

    var shouldResume: Bool {
        switch self {
        case .abnormalClosure,
             .unknownOpcode,
             .failedToDecode,
             .alreadyAuthenticated,
             .sessionTimeout,
             .voiceServerCrashed:
            return true
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .normalClosure: return "Normal Closure (1000)"
        case .abnormalClosure: return "Abnormal Closure (1006)"
        case .unknownOpcode: return "Unknown Opcode (4001)"
        case .failedToDecode: return "Failed to Decode (4002)"
        case .notAuthenticated: return "Not Authenticated (4003)"
        case .authenticationFailed: return "Authentication Failed (4004)"
        case .alreadyAuthenticated: return "Already Authenticated (4005)"
        case .sessionNoLongerValid: return "Session No Longer Valid (4006)"
        case .sessionTimeout: return "Session Timeout (4009)"
        case .serverNotFound: return "Server Not Found (4011)"
        case .unknownProtocol: return "Unknown Protocol (4012)"
        case .disconnected: return "Disconnected / Kicked (4014)"
        case .voiceServerCrashed: return "Voice Server Crashed (4015)"
        case .unknownEncryptionMode: return "Unknown Encryption Mode (4016)"
        }
    }
}

struct GatewayClose: CustomStringConvertible {
    let code: UInt16
    let reason: String?

    init(code: UInt16, reason: String? = nil) {
        self.code = code
        self.reason = reason
    }

    var closeCode: GatewayCloseCode? {
        return GatewayCloseCode(rawValue: code)
    }

    var shouldResume: Bool {
        if let mapped = closeCode {
            return mapped.shouldResume
        }

        return code != 1000 && code != 1001
    }

    var description: String {
        if let mapped = closeCode {
            return "GatewayClose(code: \(mapped), reason: \"\(reason ?? "none")\")"
        }
        return "GatewayClose(code: \(code), reason: \"\(reason ?? "none")\")"
    }
}
