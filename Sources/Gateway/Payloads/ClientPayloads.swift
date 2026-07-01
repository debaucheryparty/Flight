import Foundation

struct ClientConnectPayload: Codable {
    let user_ids: [String]
}

struct ClientDisconnectPayload: Codable {
    let user_id: String
}

struct ClientFlagsPayload: Codable {
    let user_id: String
    let flags: Int
}

struct ClientPlatformPayload: Codable {
    let user_id: String
    let platform: Int
}
