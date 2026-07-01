import CSodium
import Foundation

enum EncryptionMode: String, CaseIterable {
    case aes256GcmRtpsize = "aead_aes256_gcm_rtpsize"
    case xchacha20Poly1305Rtpsize = "aead_xchacha20_poly1305_rtpsize"

    var isLocallySupported: Bool {
        switch self {
        case .aes256GcmRtpsize:
            _ = sodium_init()

            return crypto_aead_aes256gcm_is_available() == 1
        case .xchacha20Poly1305Rtpsize:
            return true
        }
    }

    static func selectMode(from serverModes: [String]) -> EncryptionMode? {
        for mode in EncryptionMode.allCases {
            if serverModes.contains(mode.rawValue), mode.isLocallySupported {
                return mode
            }
        }
        return nil
    }
}
