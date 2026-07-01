import Foundation

struct HeartbeatAckPayload: Codable {
    let t: Int
    let seqAck: Int?

    enum CodingKeys: String, CodingKey {
        case t
        case seqAck = "seq_ack"
    }
}
