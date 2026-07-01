import Foundation

public final class UserStreamManager: @unchecked Sendable {
    private let streamsLock = Protected<[String: AsyncStream<[Int16]>.Continuation]>([:])

    public init(client: VoiceClient) {
        client.onAudioReceived = { [weak self] userId, pcm in
            self?.handleAudioReceived(userId: userId, pcm: pcm)
        }

        client.onUserDisconnect = { [weak self] userId in
            self?.handleUserDisconnect(userId: userId)
        }
    }

    public func stream(for userId: String) -> AsyncStream<[Int16]> {
        streamsLock.write { streams in
            if let existing = streams[userId] {
                existing.finish()
            }

            return AsyncStream<[Int16]> { continuation in
                streams[userId] = continuation

                continuation.onTermination = { [weak self] _ in
                    _ = self?.streamsLock.write { dict in
                        dict.removeValue(forKey: userId)
                    }
                }
            }
        }
    }

    private func handleAudioReceived(userId: String, pcm: [Int16]) {
        _ = streamsLock.read { streams in
            streams[userId]?.yield(pcm)
        }
    }

    private func handleUserDisconnect(userId: String) {
        streamsLock.write { streams in
            if let continuation = streams.removeValue(forKey: userId) {
                continuation.finish()
            }
        }
    }
}
