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
            true
        default:
            false
        }
    }

    var description: String {
        switch self {
        case .normalClosure: "Normal Closure (1000)"
        case .abnormalClosure: "Abnormal Closure (1006)"
        case .unknownOpcode: "Unknown Opcode (4001)"
        case .failedToDecode: "Failed to Decode (4002)"
        case .notAuthenticated: "Not Authenticated (4003)"
        case .authenticationFailed: "Authentication Failed (4004)"
        case .alreadyAuthenticated: "Already Authenticated (4005)"
        case .sessionNoLongerValid: "Session No Longer Valid (4006)"
        case .sessionTimeout: "Session Timeout (4009)"
        case .serverNotFound: "Server Not Found (4011)"
        case .unknownProtocol: "Unknown Protocol (4012)"
        case .disconnected: "Disconnected / Kicked (4014)"
        case .voiceServerCrashed: "Voice Server Crashed (4015)"
        case .unknownEncryptionMode: "Unknown Encryption Mode (4016)"
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
        GatewayCloseCode(rawValue: code)
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
