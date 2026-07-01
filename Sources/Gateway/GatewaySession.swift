import Foundation

struct GatewaySession: Codable {
    let serverId: String
    let userId: String
    let sessionId: String
    let token: String
    let endpoint: String

    func with(endpoint: String, token: String) -> GatewaySession {
        return GatewaySession(
            serverId: serverId,
            userId: userId,
            sessionId: sessionId,
            token: token,
            endpoint: endpoint
        )
    }
}
