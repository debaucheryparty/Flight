import Foundation

struct IdentifyPayload: Codable {
    let serverId: String
    let userId: String
    let sessionId: String
    let token: String
    let maxDaveProtocolVersion: Int

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case userId = "user_id"
        case sessionId = "session_id"
        case token
        case maxDaveProtocolVersion = "max_dave_protocol_version"
    }

    init(serverId: String, userId: String, sessionId: String, token: String, maxDaveProtocolVersion: Int = 1) {
        self.serverId = serverId
        self.userId = userId
        self.sessionId = sessionId
        self.token = token
        self.maxDaveProtocolVersion = maxDaveProtocolVersion
    }
}
