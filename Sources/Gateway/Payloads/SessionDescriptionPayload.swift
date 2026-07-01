import Foundation

struct SessionDescriptionPayload: Codable {
    let mode: String
    let secretKey: [UInt8]
    let audioCodec: String?
    let videoCodec: String?
    let daveProtocolVersion: Int?

    enum CodingKeys: String, CodingKey {
        case mode
        case secretKey = "secret_key"
        case audioCodec = "audio_codec"
        case videoCodec = "video_codec"
        case daveProtocolVersion = "dave_protocol_version"
    }

    init(
        mode: String,
        secretKey: [UInt8],
        audioCodec: String? = nil,
        videoCodec: String? = nil,
        daveProtocolVersion: Int? = nil,
    ) {
        self.mode = mode
        self.secretKey = secretKey
        self.audioCodec = audioCodec
        self.videoCodec = videoCodec
        self.daveProtocolVersion = daveProtocolVersion
    }
}
