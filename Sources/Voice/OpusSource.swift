import Foundation

public protocol OpusSource: Sendable {
    func readOpusPacket() async -> [UInt8]?
}
