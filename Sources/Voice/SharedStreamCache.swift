import Foundation

public final class SharedStreamCache: @unchecked Sendable {
    public static let shared = SharedStreamCache()

    private let cacheDirectory: URL
    private let cacheLock = Protected<[URL: URL]>([:])
    private let inflightLock = Protected<[URL: Task<URL, Error>]>([:])

    public init(directoryName: String = "FlightAudioCache") {
        let tempDir = FileManager.default.temporaryDirectory
        cacheDirectory = tempDir.appendingPathComponent(directoryName)

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil,
        )
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil,
        )
        cacheLock.write { $0.removeAll() }
    }

    public func resolve(remoteURL: URL) async throws -> URL {
        if let localURL = cacheLock.read({ $0[remoteURL] }), FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        let inflightTask = inflightLock.read { $0[remoteURL] }
        if let task = inflightTask {
            return try await task.value
        }

        let task = Task<URL, Error> {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let ext = remoteURL.pathExtension.isEmpty ? "bin" : remoteURL.pathExtension
            let hash = abs(remoteURL.absoluteString.hashValue)
            let destinationURL = cacheDirectory.appendingPathComponent("\(hash).\(ext)")

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            cacheLock.write { $0[remoteURL] = destinationURL }
            return destinationURL
        }

        inflightLock.write { $0[remoteURL] = task }

        defer {
            _ = inflightLock.write { $0.removeValue(forKey: remoteURL) }
        }

        return try await task.value
    }
}
