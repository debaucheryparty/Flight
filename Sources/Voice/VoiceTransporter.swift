import Foundation

final class VoiceTransporter: @unchecked Sendable {
    private let gateway: VoiceGateway
    private let ssrc: UInt32

    private let sequence = Protected<UInt16>(0)

    private let timestamp = Protected<UInt32>(0)

    private let nonceCounter = Protected<UInt32>(0)

    private let isSpeakingActive = Protected<Bool>(false)

    init(gateway: VoiceGateway, ssrc: UInt32) {
        self.gateway = gateway
        self.ssrc = ssrc

        sequence.write { $0 = UInt16.random(in: 0 ... UInt16.max) }
        timestamp.write { $0 = UInt32.random(in: 0 ... UInt32.max) }
    }

    func startSpeaking() async throws {
        guard isSpeakingActive.compareExchange(expected: false, desired: true) else { return }

        // tell discord we are speaking so it doesn't drop our packets
        try await gateway.sendSpeaking(isSpeaking: true, ssrc: ssrc)
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    func stopSpeaking() async throws {
        guard isSpeakingActive.compareExchange(expected: true, desired: false) else { return }

        try await gateway.sendSpeaking(isSpeaking: false, ssrc: ssrc)
    }

    func sendFrame(
        _ opusPayload: [UInt8],
        encryption: VoiceEncryption,
        udp: UDPConnection,
        daveSessionManager: DaveSessionManager? = nil
    ) async throws {
        if !isSpeakingActive.read({ $0 }) {
            try await startSpeaking()
        }

        // seq and ts must increment and wrap cleanly for rtp
        let seq = sequence.write { current -> UInt16 in
            let prev = current
            current = current &+ 1
            return prev
        }

        let ts = timestamp.write { current -> UInt32 in
            let prev = current
            current = current &+ 960
            return prev
        }

        let nonce = nonceCounter.write { current -> UInt32 in
            let prev = current
            current = current &+ 1
            return prev
        }

        // dave e2ee comes first if enabled
        var mediaPayload = opusPayload
        if let daveSessionManager {
            do {
                let encryptedData = try await daveSessionManager.encrypt(
                    ssrc: ssrc,
                    data: Data(opusPayload)
                )
                mediaPayload = Array(encryptedData)
            } catch {
                throw VoiceError.handshakeFailed("DAVE encryption failed: \(error)")
            }
        }

        let rtpHeader = RTPPacket.makeHeader(sequence: seq, timestamp: ts, ssrc: ssrc)

        let encryptedPayload = try encryption.encrypt(
            payload: mediaPayload,
            rtpHeader: rtpHeader,
            nonceCounter: nonce
        )

        let rtpPacket = RTPPacket.makePacket(header: rtpHeader, encryptedPayload: encryptedPayload)
        try udp.send(bytes: rtpPacket)
    }

    var currentSequence: UInt16 {
        sequence.read { $0 }
    }

    var currentTimestamp: UInt32 {
        timestamp.read { $0 }
    }

    #if DEBUG
        func setSequenceForTesting(_ seq: UInt16) {
            sequence.write { $0 = seq }
        }

        func setTimestampForTesting(_ ts: UInt32) {
            timestamp.write { $0 = ts }
        }
    #endif
}
