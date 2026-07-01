import Foundation

public struct TrackMetadata: Sendable, Codable {
    public var title: String
    public var artist: String?
    public var duration: Double?

    public init(title: String, artist: String? = nil, duration: Double? = nil) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

public enum TrackSource: Sendable {
    case pcm(any AudioSource)
    case opus(any OpusSource)
}

public final class Track: Sendable {
    public let source: TrackSource
    public let metadata: TrackMetadata

    public init(source: TrackSource, metadata: TrackMetadata) {
        self.source = source
        self.metadata = metadata
    }

    public convenience init(pcmSource: any AudioSource, metadata: TrackMetadata) {
        self.init(source: .pcm(pcmSource), metadata: metadata)
    }

    public convenience init(opusSource: any OpusSource, metadata: TrackMetadata) {
        self.init(source: .opus(opusSource), metadata: metadata)
    }
}

public final class QueueManager: Sendable {
    public enum LoopMode: String, Sendable, Codable {
        case off
        case track
        case queue
    }

    private let list = Protected<[Track]>([])
    private let currentIndex = Protected<Int>(0)
    private let loopMode = Protected<LoopMode>(.off)

    public init() {}

    public var tracks: [Track] {
        list.read { $0 }
    }

    public var currentTrack: Track? {
        list.read { tracks in
            let idx = currentIndex.read { $0 }
            guard idx >= 0, idx < tracks.count else { return nil }
            return tracks[idx]
        }
    }

    public func enqueue(_ track: Track) {
        list.write { $0.append(track) }
    }

    public func enqueue(_ tracks: [Track]) {
        list.write { $0.append(contentsOf: tracks) }
    }

    public func clear() {
        list.write { $0.removeAll() }
        currentIndex.write { $0 = 0 }
    }

    public func setLoopMode(_ mode: LoopMode) {
        loopMode.write { $0 = mode }
    }

    public var currentLoopMode: LoopMode {
        loopMode.read { $0 }
    }

    public func advance() -> Track? {
        let mode = loopMode.read { $0 }
        let tracks = list.read { $0 }
        guard !tracks.isEmpty else { return nil }

        switch mode {
        case .track:
            return currentTrack
        case .queue:
            _ = currentIndex.write { idx -> Int in
                let nextIdx = idx + 1
                if nextIdx >= tracks.count {
                    return 0
                }
                return nextIdx
            }
            return currentTrack
        case .off:
            currentIndex.write { $0 += 1 }
            return currentTrack
        }
    }

    public func skip() -> Track? {
        let tracks = list.read { $0 }
        guard !tracks.isEmpty else { return nil }

        let mode = loopMode.read { $0 }
        switch mode {
        case .queue:
            _ = currentIndex.write { idx in
                let nextIdx = idx + 1
                return nextIdx >= tracks.count ? 0 : nextIdx
            }
        default:
            currentIndex.write { $0 += 1 }
        }
        return currentTrack
    }

    public func resetIndex() {
        currentIndex.write { $0 = 0 }
    }

    @discardableResult
    public func setIndex(_ index: Int) -> Bool {
        let count = list.read { $0.count }
        guard index >= 0 && index < count else { return false }
        currentIndex.write { $0 = index }
        return true
    }
}
