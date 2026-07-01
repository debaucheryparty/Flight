import CSodium
import Foundation

struct VoiceEncryption {
    let secretKey: [UInt8]
    let mode: EncryptionMode

    init(secretKey: [UInt8], mode: EncryptionMode) {
        let status = sodium_init()
        if status < 0 {
            print("Warning: libsodium initialization failed with status \(status)")
        }
        self.secretKey = secretKey
        self.mode = mode
    }

    func encrypt(
        payload: [UInt8],
        rtpHeader: [UInt8],
        nonceCounter: UInt32,
    ) throws -> [UInt8] {
        let nonce = RTPNonce.makeNonce(mode: mode, counter: nonceCounter)

        switch mode {
        case .aes256GcmRtpsize:
            let macBytes = Int(crypto_aead_aes256gcm_abytes())
            var ciphertext = [UInt8](repeating: 0, count: payload.count + macBytes)
            var ciphertextLen: UInt64 = 0

            let result = crypto_aead_aes256gcm_encrypt(
                &ciphertext,
                &ciphertextLen,
                payload,
                UInt64(payload.count),
                rtpHeader,
                UInt64(rtpHeader.count),
                nil,
                nonce,
                secretKey,
            )

            guard result == 0 else {
                throw VoiceError.encryptionFailed("AES-GCM encryption failed with code \(result)")
            }

            if ciphertext.count > ciphertextLen {
                ciphertext.removeSubrange(Int(ciphertextLen) ..< ciphertext.count)
            }

            ciphertext.append(contentsOf: RTPNonce.serializeCounter(nonceCounter))
            return ciphertext

        case .xchacha20Poly1305Rtpsize:
            let macBytes = Int(crypto_aead_xchacha20poly1305_ietf_abytes())
            var ciphertext = [UInt8](repeating: 0, count: payload.count + macBytes)
            var ciphertextLen: UInt64 = 0

            let result = crypto_aead_xchacha20poly1305_ietf_encrypt(
                &ciphertext,
                &ciphertextLen,
                payload,
                UInt64(payload.count),
                rtpHeader,
                UInt64(rtpHeader.count),
                nil,
                nonce,
                secretKey,
            )

            guard result == 0 else {
                throw VoiceError.encryptionFailed("XChaCha20-Poly1305 encryption failed with code \(result)")
            }

            if ciphertext.count > ciphertextLen {
                ciphertext.removeSubrange(Int(ciphertextLen) ..< ciphertext.count)
            }

            ciphertext.append(contentsOf: RTPNonce.serializeCounter(nonceCounter))
            return ciphertext
        }
    }

    func decrypt(
        payload: [UInt8],
        rtpHeader: [UInt8],
        sequence: UInt16,
    ) throws -> [UInt8] {
        guard payload.count >= 4 else {
            throw VoiceError.encryptionFailed("Payload too short for nonce extraction")
        }

        let ciphertextDropped = Array(payload.dropLast(4))
        let nonceBytes = Array(payload.suffix(4))
        let nonceCounterBE = UInt32(nonceBytes[0]) << 24 | UInt32(nonceBytes[1]) << 16 | UInt32(nonceBytes[2]) << 8 | UInt32(nonceBytes[3])
        let nonceCounterLE = UInt32(nonceBytes[3]) << 24 | UInt32(nonceBytes[2]) << 16 | UInt32(nonceBytes[1]) << 8 | UInt32(nonceBytes[0])

        let nonceBE = RTPNonce.makeNonce(mode: mode, counter: nonceCounterBE)
        let nonceLE = RTPNonce.makeNonce(mode: mode, counter: nonceCounterLE)
        let nonceSeq = RTPNonce.makeNonce(mode: mode, counter: UInt32(sequence))

        let candidates = [
            (ciphertext: ciphertextDropped, nonce: nonceBE, aad: rtpHeader, desc: "nonceBE_fullAAD"),
            (ciphertext: ciphertextDropped, nonce: nonceLE, aad: rtpHeader, desc: "nonceLE_fullAAD"),
            (ciphertext: ciphertextDropped, nonce: nonceBE, aad: Array(rtpHeader.prefix(12)), desc: "nonceBE_12bAAD"),
            (ciphertext: ciphertextDropped, nonce: nonceLE, aad: Array(rtpHeader.prefix(12)), desc: "nonceLE_12bAAD"),
            (ciphertext: payload, nonce: nonceSeq, aad: rtpHeader, desc: "nonceSeq_fullAAD_fullPayload"),
            (ciphertext: payload, nonce: nonceSeq, aad: Array(rtpHeader.prefix(12)), desc: "nonceSeq_12bAAD_fullPayload"),
        ]

        switch mode {
        case .aes256GcmRtpsize:
            let macBytes = Int(crypto_aead_aes256gcm_abytes())
            guard payload.count >= macBytes else {
                throw VoiceError.encryptionFailed("Ciphertext too short")
            }

            for candidate in candidates {
                var plaintext = [UInt8](repeating: 0, count: candidate.ciphertext.count - macBytes)
                var plaintextLen: UInt64 = 0

                let result = crypto_aead_aes256gcm_decrypt(
                    &plaintext,
                    &plaintextLen,
                    nil,
                    candidate.ciphertext,
                    UInt64(candidate.ciphertext.count),
                    candidate.aad,
                    UInt64(candidate.aad.count),
                    candidate.nonce,
                    secretKey,
                )

                if result == 0 {
                    if plaintext.count > plaintextLen {
                        plaintext.removeSubrange(Int(plaintextLen) ..< plaintext.count)
                    }
                    return plaintext
                }
            }
            throw VoiceError.encryptionFailed("AES-GCM decryption failed for all candidates")

        case .xchacha20Poly1305Rtpsize:
            let macBytes = Int(crypto_aead_xchacha20poly1305_ietf_abytes())
            guard payload.count >= macBytes else {
                throw VoiceError.encryptionFailed("Ciphertext too short")
            }

            for candidate in candidates {
                var plaintext = [UInt8](repeating: 0, count: candidate.ciphertext.count - macBytes)
                var plaintextLen: UInt64 = 0

                let result = crypto_aead_xchacha20poly1305_ietf_decrypt(
                    &plaintext,
                    &plaintextLen,
                    nil,
                    candidate.ciphertext,
                    UInt64(candidate.ciphertext.count),
                    candidate.aad,
                    UInt64(candidate.aad.count),
                    candidate.nonce,
                    secretKey,
                )

                if result == 0 {
                    if plaintext.count > plaintextLen {
                        plaintext.removeSubrange(Int(plaintextLen) ..< plaintext.count)
                    }
                    return plaintext
                }
            }
            throw VoiceError.encryptionFailed("XChaCha20-Poly1305 decryption failed for all candidates")
        }
    }
}
