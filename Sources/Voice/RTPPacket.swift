import Foundation

struct ParsedRTP {
    let header: [UInt8]
    let sequence: UInt16
    let timestamp: UInt32
    let ssrc: UInt32
    let payload: [UInt8]
}

enum RTPPacket {
    static func makeHeader(
        sequence: UInt16,
        timestamp: UInt32,
        ssrc: UInt32
    ) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 12)

        header[0] = 0x80

        header[1] = 0x78

        header[2] = UInt8((sequence >> 8) & 0xFF)
        header[3] = UInt8(sequence & 0xFF)

        header[4] = UInt8((timestamp >> 24) & 0xFF)
        header[5] = UInt8((timestamp >> 16) & 0xFF)
        header[6] = UInt8((timestamp >> 8) & 0xFF)
        header[7] = UInt8(timestamp & 0xFF)

        header[8] = UInt8((ssrc >> 24) & 0xFF)
        header[9] = UInt8((ssrc >> 16) & 0xFF)
        header[10] = UInt8((ssrc >> 8) & 0xFF)
        header[11] = UInt8(ssrc & 0xFF)

        return header
    }

    static func makePacket(
        header: [UInt8],
        encryptedPayload: [UInt8]
    ) -> [UInt8] {
        return header + encryptedPayload
    }

    static func parse(bytes: [UInt8]) -> ParsedRTP? {
        guard bytes.count >= 12 else { return nil }

        guard (bytes[0] >> 6) == 2 else { return nil }

        let hasExtension = (bytes[0] & 0x10) != 0
        let csrcCount = Int(bytes[0] & 0x0F)

        let sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let timestamp = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        let ssrc = UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])

        var headerLen = 12 + (csrcCount * 4)
        guard bytes.count >= headerLen else { return nil }

        if hasExtension {
            guard bytes.count >= headerLen + 4 else { return nil }

            let extLenWords = Int(bytes[headerLen + 2]) << 8 | Int(bytes[headerLen + 3])
            headerLen += 4 + (extLenWords * 4)
            guard bytes.count >= headerLen else { return nil }
        }

        let payloadLength = bytes.count - headerLen

        let header = Array(bytes[0 ..< headerLen])
        let payload = Array(bytes[headerLen ..< (headerLen + payloadLength)])

        return ParsedRTP(
            header: header,
            sequence: sequence,
            timestamp: timestamp,
            ssrc: ssrc,
            payload: payload
        )
    }
}
