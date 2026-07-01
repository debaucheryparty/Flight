import Foundation

public enum PlayerEvent: Sendable {
    case trackStarted(Track)
    case trackFinished(Track, reason: FinishReason)
    case stateChanged(from: AudioPlayer.State, to: AudioPlayer.State)
    case error(Error)

    public enum FinishReason: Sendable {
        case finished
        case stopped
        case skipped
    }
}

public final class AudioPlayer: Sendable {
    public enum State: String, Sendable, Codable {
        case stopped
        case playing
        case paused
    }

    private let client: VoiceClient
    private let encoder: OpusEncoder
    private let stateLock = Protected<State>(.stopped)
    private let currentTrackLock = Protected<Track?>(nil)
    private let schedulerLock = Protected<FrameScheduler?>(nil)
    private let volumeLock = Protected<Float>(1.0)
    private let activeQueueLock = Protected<QueueManager?>(nil)

    private let eventController = Protected<AsyncStream<PlayerEvent>.Continuation?>(nil)

    public init(client: VoiceClient) throws {
        self.client = client
        encoder = try OpusEncoder()
    }

    public var state: State {
        stateLock.read { $0 }
    }

    public var currentTrack: Track? {
        currentTrackLock.read { $0 }
    }

    public var volume: Float {
        volumeLock.read { $0 }
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        volumeLock.write { $0 = clamped }
    }

    public var events: AsyncStream<PlayerEvent> {
        AsyncStream { continuation in
            eventController.write { $0 = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.eventController.write { $0 = nil }
            }
        }
    }

    private func emit(_ event: PlayerEvent) {
        _ = eventController.read { $0?.yield(event) }
    }

    public func play(_ track: Track) {
        activeQueueLock.write { $0 = nil }
        startTrack(track)
    }

    public func play(queue: QueueManager) {
        activeQueueLock.write { $0 = queue }
        if let current = queue.currentTrack {
            startTrack(current)
        } else if let next = queue.advance() {
            startTrack(next)
        } else {
            stop()
        }
    }

    public func pause() {
        stateLock.write { state in
            guard state == .playing else { return }
            state = .paused
            schedulerLock.read { $0?.stop() }

            Task { try? await self.client.stopSpeaking() }

            emit(.stateChanged(from: .playing, to: .paused))
        }
    }

    public func resume() {
        stateLock.write { state in
            guard state == .paused else { return }
            state = .playing
            schedulerLock.read { $0?.start() }
            emit(.stateChanged(from: .paused, to: .playing))
        }
    }

    public func stop() {
        stateLock.write { state in
            let oldState = state
            state = .stopped

            schedulerLock.read { $0?.stop() }
            schedulerLock.write { $0 = nil }

            Task { try? await self.client.stopSpeaking() }

            let oldTrack = currentTrackLock.write { old -> Track? in
                let temp = old
                old = nil
                return temp
            }

            if oldState != .stopped {
                emit(.stateChanged(from: oldState, to: .stopped))
            }

            if let track = oldTrack {
                emit(.trackFinished(track, reason: .stopped))
            }
        }
    }

    public func skip() {
        guard let queue = activeQueueLock.read({ $0 }),
              let track = currentTrackLock.read({ $0 }) else { return }

        emit(.trackFinished(track, reason: .skipped))

        if let nextTrack = queue.skip() {
            startTrack(nextTrack)
        } else {
            stop()
        }
    }

    private func startTrack(_ track: Track) {
        stateLock.write { state in
            let oldState = state
            state = .playing

            schedulerLock.read { $0?.stop() }

            currentTrackLock.write { $0 = track }

            // trigger a frame read exactly every 20ms to match discord voice timing
            let scheduler = FrameScheduler(tickMs: 20) { [weak self] in
                guard let self = self else { return }

                guard self.stateLock.read({ $0 }) == .playing else { return }
                guard let activeTrack = self.currentTrackLock.read({ $0 }) else { return }

                switch activeTrack.source {
                case let .pcm(pcmSource):
                    if var pcmFrame = await pcmSource.readFrame() {
                        // multiply samples by volume but cap it to 16bit so it doesnt crackle
                        self.applyVolume(&pcmFrame, scale: self.volumeLock.read { $0 })
                        do {
                            let opusData = try self.encoder.encode(pcm: pcmFrame, frameSize: 960)
                            try await self.client.sendOpusFrame(opusData)
                        } catch {
                            self.emit(.error(error))
                        }
                    } else {
                        await self.handleTrackFinished(activeTrack, reason: .finished)
                    }
                case let .opus(opusSource):
                    if let opusData = await opusSource.readOpusPacket() {
                        do {
                            try await self.client.sendOpusFrame(opusData)
                        } catch {
                            self.emit(.error(error))
                        }
                    } else {
                        await self.handleTrackFinished(activeTrack, reason: .finished)
                    }
                }
            }

            schedulerLock.write { $0 = scheduler }
            scheduler.start()

            if oldState != .playing {
                emit(.stateChanged(from: oldState, to: .playing))
            }
            emit(.trackStarted(track))
        }
    }

    private func handleTrackFinished(_ track: Track, reason: PlayerEvent.FinishReason) async {
        guard currentTrackLock.read({ $0 === track }) else { return }

        emit(.trackFinished(track, reason: reason))

        if let queue = activeQueueLock.read({ $0 }) {
            if let nextTrack = queue.advance() {
                startTrack(nextTrack)
            } else {
                stop()
            }
        } else {
            stop()
        }
    }

    private func applyVolume(_ pcm: inout [Int16], scale: Float) {
        // fast return if volume is at 100 percent to save cpu
        if scale >= 0.99, scale <= 1.01 { return }
        for i in 0 ..< pcm.count {
            let val = Float(pcm[i]) * scale
            if val > Float(Int16.max) { pcm[i] = Int16.max }
            else if val < Float(Int16.min) { pcm[i] = Int16.min }
            else { pcm[i] = Int16(val) }
        }
    }
}
