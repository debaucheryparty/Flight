import Foundation

enum RTPNonce {
    static func makeNonce(
        mode: EncryptionMode,
        counter: UInt32,
    ) -> [UInt8] {
        switch mode {
        case .aes256GcmRtpsize:
            var nonce = [UInt8](repeating: 0, count: 12)
            nonce[0] = UInt8((counter >> 24) & 0xFF)
            nonce[1] = UInt8((counter >> 16) & 0xFF)
            nonce[2] = UInt8((counter >> 8) & 0xFF)
            nonce[3] = UInt8(counter & 0xFF)
            return nonce

        case .xchacha20Poly1305Rtpsize:
            var nonce = [UInt8](repeating: 0, count: 24)
            nonce[0] = UInt8((counter >> 24) & 0xFF)
            nonce[1] = UInt8((counter >> 16) & 0xFF)
            nonce[2] = UInt8((counter >> 8) & 0xFF)
            nonce[3] = UInt8(counter & 0xFF)
            return nonce
        }
    }

    static func serializeCounter(_ counter: UInt32) -> [UInt8] {
        [
            UInt8((counter >> 24) & 0xFF),
            UInt8((counter >> 16) & 0xFF),
            UInt8((counter >> 8) & 0xFF),
            UInt8(counter & 0xFF),
        ]
    }
}
