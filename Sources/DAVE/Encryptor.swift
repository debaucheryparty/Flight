import CLibdave
import Foundation

class Encryptor {
    private let encryptorHandle: DAVEEncryptorHandle

    init() {
        encryptorHandle = daveEncryptorCreate()
    }

    deinit {
        daveEncryptorDestroy(self.encryptorHandle)
    }

    func setKeyRatchet(keyRatchet: KeyRatchet) {
        daveEncryptorSetKeyRatchet(encryptorHandle, keyRatchet.handle)
    }

    func setPassthroughMode(enabled: Bool) {
        daveEncryptorSetPassthroughMode(encryptorHandle, enabled)
    }

    func assignSsrcToCodec(ssrc: UInt32, codec: DAVECodec) {
        daveEncryptorAssignSsrcToCodec(encryptorHandle, ssrc, codec)
    }

    func encrypt(
        ssrc: UInt32,
        data: Data,
        mediaType: MediaType = .audio,
    ) throws(EncryptError) -> Data {
        let maxOutputLength = daveEncryptorGetMaxCiphertextByteSize(encryptorHandle, mediaType, data.count)
        var encryptedData = Data(count: maxOutputLength)
        var outputLength = 0

        let result = encryptedData.withUnsafeMutableBytes { encryptedData in
            data.withUnsafeBytes { data in
                let encryptedData = encryptedData.bindMemory(to: UInt8.self)
                let data = data.bindMemory(to: UInt8.self)

                return daveEncryptorEncrypt(
                    self.encryptorHandle,
                    mediaType,
                    ssrc,
                    data.baseAddress!,
                    data.count,
                    encryptedData.baseAddress!,
                    encryptedData.count,
                    &outputLength,
                )
            }
        }

        if let error = EncryptError(rawValue: result) {
            throw error
        }

        encryptedData.removeSubrange(outputLength ..< encryptedData.count)
        return encryptedData
    }
}

public enum EncryptError: Error {
    case encryptionFailure
    case unknown(code: DAVEEncryptorResultCode)

    init?(rawValue: DAVEEncryptorResultCode) {
        switch rawValue {
        case DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS:
            return nil
        case DAVE_ENCRYPTOR_RESULT_CODE_ENCRYPTION_FAILURE:
            self = .encryptionFailure
        default:
            self = .unknown(code: rawValue)
        }
    }
}
