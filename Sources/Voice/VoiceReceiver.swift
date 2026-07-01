import Foundation

final class VoiceReceiver: @unchecked Sendable {
    private let gateway: VoiceGateway
    private let encryption: VoiceEncryption
    private let daveSessionManager: DaveSessionManager?
    private let logger: Logger

    private let decoders = Protected<[UInt32: OpusDecoder]>([:])
    private let jitterBuffers = Protected<[UInt32: JitterBuffer]>([:])

    var onAudioReceived: (@Sendable (_ userId: String, _ pcm: [Int16]) -> Void)?

    init(
        gateway: VoiceGateway,
        encryption: VoiceEncryption,
        daveSessionManager: DaveSessionManager?,
        logger: Logger = Logger(label: "Flight.VoiceReceiver"),
    ) {
        self.gateway = gateway
        self.encryption = encryption
        self.daveSessionManager = daveSessionManager
        self.logger = logger
    }

    func handleIncomingPacket(_ bytes: [UInt8]) {
        Task {
            guard let parsed = RTPPacket.parse(bytes: bytes) else {
                logger.warning("Failed to parse RTP packet")
                return
            }

            guard parsed.payload.count > 0 else { return }

            let userIdMap = gateway.ssrcToUserIdLock.read { $0 }
            guard let userId = userIdMap[parsed.ssrc] else {
                return
            }

            do {
                let decryptedTransportPayload = try encryption.decrypt(
                    payload: parsed.payload,
                    rtpHeader: parsed.header,
                    sequence: parsed.sequence,
                )

                var mediaPayload = decryptedTransportPayload
                if let daveSessionManager {
                    if let e2eDecrypted = try await daveSessionManager.decrypt(
                        userId: userId,
                        data: Data(decryptedTransportPayload),
                    ) {
                        mediaPayload = Array(e2eDecrypted)
                    } else {
                        logger.warning("DAVE decryption returned nil for user \(userId)")
                        return
                    }
                }

                guard !mediaPayload.isEmpty else { return }

                let jitterBuffer = getOrCreateJitterBuffer(for: parsed.ssrc, userId: userId)
                await jitterBuffer.push(sequence: parsed.sequence, timestamp: parsed.timestamp, payload: mediaPayload)

            } catch {
                let hexDump = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.warning("Failed to process inbound audio packet for SSRC \(parsed.ssrc): \(error). Packet bytes: \(hexDump)")
            }
        }
    }

    private func getOrCreateDecoder(for ssrc: UInt32) throws -> OpusDecoder {
        try decoders.write { dict in
            if let existing = dict[ssrc] {
                return existing
            }
            let newDecoder = try OpusDecoder(sampleRate: 48000, channels: 2)
            dict[ssrc] = newDecoder
            return newDecoder
        }
    }

    private func getOrCreateJitterBuffer(for ssrc: UInt32, userId: String) -> JitterBuffer {
        jitterBuffers.write { dict in
            if let existing = dict[ssrc] {
                return existing
            }
            let buffer = JitterBuffer(ssrc: ssrc, logger: logger)
            Task { [self] in
                await buffer.setOnFrameReady { [weak self] payload in
                    guard let self else { return }
                    do {
                        let decoder = try getOrCreateDecoder(for: ssrc)
                        let pcm = try decoder.decode(opusData: payload)
                        onAudioReceived?(userId, pcm)
                    } catch {
                        logger.warning("Failed to decode frame from jitter buffer for SSRC \(ssrc): \(error)")
                    }
                }
            }
            dict[ssrc] = buffer
            return buffer
        }
    }

    func removeUser(userId: String) {
        let userIdMap = gateway.ssrcToUserIdLock.read { $0 }
        let ssrces = userIdMap.compactMap { $0.value == userId ? $0.key : nil }

        decoders.write { dict in
            for ssrc in ssrces {
                dict.removeValue(forKey: ssrc)
            }
        }

        jitterBuffers.write { dict in
            for ssrc in ssrces {
                if let buffer = dict.removeValue(forKey: ssrc) {
                    Task { await buffer.stop() }
                }
            }
        }
        logger.info("Cleaned up decoder and jitter buffer state for user \(userId) (SSRCs: \(ssrces))")
    }
}
