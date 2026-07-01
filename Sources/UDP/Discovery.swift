import Foundation

enum Discovery {
    static func makeRequest(ssrc: UInt32) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 74)

        let type: UInt16 = 1
        packet[0] = UInt8((type >> 8) & 0xFF)
        packet[1] = UInt8(type & 0xFF)

        let length: UInt16 = 70
        packet[2] = UInt8((length >> 8) & 0xFF)
        packet[3] = UInt8(length & 0xFF)

        packet[4] = UInt8((ssrc >> 24) & 0xFF)
        packet[5] = UInt8((ssrc >> 16) & 0xFF)
        packet[6] = UInt8((ssrc >> 8) & 0xFF)
        packet[7] = UInt8(ssrc & 0xFF)

        return packet
    }

    static func parseResponse(bytes: [UInt8], expectedSSRC: UInt32) throws -> (ip: String, port: UInt16) {
        guard bytes.count == 74 else {
            throw VoiceError.handshakeFailed("Invalid discovery response packet size: expected 74, got \(bytes.count) bytes")
        }

        let type = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        guard type == 2 else {
            throw VoiceError.handshakeFailed("Invalid discovery response packet type: expected 2, got \(type)")
        }

        let length = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
        guard length == 70 else {
            throw VoiceError.handshakeFailed("Invalid discovery response packet length field: expected 70, got \(length)")
        }

        let ssrc = (UInt32(bytes[4]) << 24) | (UInt32(bytes[5]) << 16) | (UInt32(bytes[6]) << 8) | UInt32(bytes[7])
        guard ssrc == expectedSSRC else {
            throw VoiceError.handshakeFailed("SSRC mismatch in discovery response: expected \(expectedSSRC), got \(ssrc)")
        }

        let ipBytes = bytes[8 ..< 72]
        guard let nullIndex = ipBytes.firstIndex(of: 0) else {
            throw VoiceError.handshakeFailed("External IP string is not null-terminated")
        }

        let ipLength = nullIndex - ipBytes.startIndex
        guard ipLength > 0 else {
            throw VoiceError.handshakeFailed("External IP string is empty")
        }

        let ipData = Data(bytes[8 ..< (8 + ipLength)])
        guard let ipString = String(data: ipData, encoding: .utf8) else {
            throw VoiceError.handshakeFailed("External IP string is not valid UTF-8")
        }

        let port = (UInt16(bytes[72]) << 8) | UInt16(bytes[73])

        return (ipString, port)
    }
}
