import Foundation

struct SelectProtocolPayload: Codable {
    let protocolName: String
    let data: ConnectionData

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case data
    }

    struct ConnectionData: Codable {
        let address: String
        let port: UInt16
        let mode: String

        init(address: String, port: UInt16, mode: String) {
            self.address = address
            self.port = port
            self.mode = mode
        }
    }

    init(protocolName: String = "udp", address: String, port: UInt16, mode: String) {
        self.protocolName = protocolName
        data = ConnectionData(address: address, port: port, mode: mode)
    }
}
