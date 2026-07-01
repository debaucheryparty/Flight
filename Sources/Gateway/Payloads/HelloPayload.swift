import Foundation

struct HelloPayload: Codable {
    let heartbeatInterval: Double

    enum CodingKeys: String, CodingKey {
        case heartbeatInterval = "heartbeat_interval"
    }
}
