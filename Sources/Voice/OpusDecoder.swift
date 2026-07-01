import COpus
import Foundation

public final class OpusDecoder: @unchecked Sendable {
    private let decoder: OpaquePointer
    private let sampleRate: Int
    private let channels: Int

    public init(sampleRate: Int = 48000, channels: Int = 2) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        var error: Int32 = 0
        guard let dec = opus_decoder_create(
            Int32(sampleRate),
            Int32(channels),
            &error
        ), error == OPUS_OK else {
            throw VoiceError.opusError(error, "Failed to initialize Opus decoder")
        }
        decoder = dec
    }

    deinit {
        opus_decoder_destroy(decoder)
    }

    public func decode(opusData: [UInt8], frameSize: Int = 960, isFEC: Bool = false) throws -> [Int16] {
        var pcmOut = [Int16](repeating: 0, count: frameSize * channels)

        let decodedSamples: Int32

        if opusData.isEmpty {
            decodedSamples = opus_decode(
                decoder,
                nil,
                0,
                &pcmOut,
                Int32(frameSize),
                isFEC ? 1 : 0
            )
        } else {
            decodedSamples = opus_decode(
                decoder,
                opusData,
                Int32(opusData.count),
                &pcmOut,
                Int32(frameSize),
                isFEC ? 1 : 0
            )
        }

        guard decodedSamples >= 0 else {
            throw VoiceError.opusError(decodedSamples, "Opus decode failed")
        }

        if Int(decodedSamples) < frameSize {
            pcmOut.removeLast((frameSize - Int(decodedSamples)) * channels)
        }

        return pcmOut
    }
}
