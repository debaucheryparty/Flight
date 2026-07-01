import Foundation

public enum DCAParserError: Error {
    case invalidMagicBytes
    case eof
    case fileReadError
    case invalidJSON
}

public final class DCAParser: OpusSource, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let readLock = NSLock()

    public let metadata: [String: Any]?

    public init(url: URL) throws {
        fileHandle = try FileHandle(forReadingFrom: url)

        let magic = try fileHandle.read(upToCount: 4)
        guard magic?.count == 4, String(data: magic!, encoding: .utf8) == "DCA1" else {
            throw DCAParserError.invalidMagicBytes
        }

        let jsonSizeData = try fileHandle.read(upToCount: 4)
        guard let jsonSizeData, jsonSizeData.count == 4 else {
            throw DCAParserError.eof
        }
        let jsonSize = Int(jsonSizeData.withUnsafeBytes { $0.load(as: Int32.self).littleEndian })

        let jsonData = try fileHandle.read(upToCount: jsonSize)
        guard let jsonData, jsonData.count == jsonSize else {
            throw DCAParserError.eof
        }

        metadata = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
    }

    deinit {
        try? fileHandle.close()
    }

    public func readOpusPacket() async -> [UInt8]? {
        readPacketSynchronously()
    }

    private func readPacketSynchronously() -> [UInt8]? {
        readLock.lock()
        defer { readLock.unlock() }

        do {
            guard let sizeData = try fileHandle.read(upToCount: 2), sizeData.count == 2 else {
                return nil
            }

            let frameSize = Int(sizeData.withUnsafeBytes { $0.load(as: Int16.self).littleEndian })
            guard frameSize > 0 else { return nil }

            guard let frameData = try fileHandle.read(upToCount: frameSize), frameData.count == frameSize else {
                return nil
            }

            return [UInt8](frameData)
        } catch {
            return nil
        }
    }
}
