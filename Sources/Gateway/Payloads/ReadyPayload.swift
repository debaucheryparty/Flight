import Foundation

struct ReadyPayload: Codable {
    let ssrc: UInt32
    let ip: String
    let port: UInt16
    let modes: [String]
}
