import COpus
import Foundation

public final class OpusEncoder: @unchecked Sendable {
    private let encoder: OpaquePointer
    private let channels: Int

    public init(sampleRate: Int = 48000, channels: Int = 2) throws {
        self.channels = channels
        var error: Int32 = 0
        guard let enc = opus_encoder_create(
            Int32(sampleRate),
            Int32(channels),
            OPUS_APPLICATION_AUDIO,
            &error
        ) else {
            throw VoiceError.opusError(error, "Failed to create Opus encoder")
        }
        encoder = enc

        let setBitrateResult = flight_opus_encoder_set_bitrate(encoder, 128_000)
        if setBitrateResult != OPUS_OK {
            print("Warning: Failed to set bitrate on Opus encoder: \(setBitrateResult)")
        }

        let setVBRResult = flight_opus_encoder_set_vbr(encoder, 1)
        if setVBRResult != OPUS_OK {
            print("Warning: Failed to enable VBR on Opus encoder: \(setVBRResult)")
        }
    }

    deinit {
        opus_encoder_destroy(encoder)
    }

    public func encode(pcm: [Int16], frameSize: Int) throws -> [UInt8] {
        guard pcm.count >= frameSize * channels else {
            throw VoiceError.opusError(-1, "PCM buffer is too small for the requested frame size.")
        }

        var outputBuffer = [UInt8](repeating: 0, count: 4000)
        let bytesEncoded = opus_encode(
            encoder,
            pcm,
            Int32(frameSize),
            &outputBuffer,
            Int32(outputBuffer.count)
        )

        guard bytesEncoded >= 0 else {
            throw VoiceError.opusError(bytesEncoded, "Opus encoding failed")
        }

        return Array(outputBuffer[0 ..< Int(bytesEncoded)])
    }
}
