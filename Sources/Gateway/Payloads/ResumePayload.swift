import Foundation

struct ResumePayload: Codable {
    let serverId: String
    let sessionId: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case sessionId = "session_id"
        case token
    }
}
