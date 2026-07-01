import Foundation

struct SpeakingPayload: Codable {
    let speaking: Int
    let delay: Int?
    let ssrc: UInt32
    let user_id: String?

    init(speaking: Int, delay: Int? = 0, ssrc: UInt32, user_id: String? = nil) {
        self.speaking = speaking
        self.delay = delay
        self.ssrc = ssrc
        self.user_id = user_id
    }
}
