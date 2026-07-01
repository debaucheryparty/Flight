import Foundation

public final class AudioMixer: AudioSource, @unchecked Sendable {
    private struct TrackedSource {
        let id: UUID
        let source: any AudioSource
    }

    private let sourcesLock = Protected<[TrackedSource]>([])

    public init() {}

    @discardableResult
    public func addSource(_ source: any AudioSource) -> UUID {
        let id = UUID()
        sourcesLock.write { $0.append(TrackedSource(id: id, source: source)) }
        return id
    }

    public func removeSource(id: UUID) {
        sourcesLock.write { $0.removeAll { $0.id == id } }
    }

    public func clearSources() {
        sourcesLock.write { $0.removeAll() }
    }

    public func readFrame() async -> [Int16]? {
        let activeSources = sourcesLock.read { $0 }
        if activeSources.isEmpty {
            return nil
        }

        // fetch all audio concurrently but timeout after 20ms to avoid lagging the stream
        let results = await withThrowingTaskGroup(of: (UUID, [Int16]?).self) { group in
            for tracked in activeSources {
                group.addTask {
                    let frame = await tracked.source.readFrame()
                    return (tracked.id, frame)
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000)
                throw CancellationError()
            }

            var collected = [(UUID, [Int16]?)]()
            do {
                for try await result in group {
                    collected.append(result)
                    if collected.count == activeSources.count {
                        group.cancelAll()
                        break
                    }
                }
            } catch {
                group.cancelAll()
            }
            return collected
        }

        // sum all sources into 32bit integers first
        var activeSourcesFinished = 0
        var mixedFrame = [Int32](repeating: 0, count: 1920)
        var finishedIds = [UUID]()

        for (id, frame) in results {
            if let frame = frame {
                for i in 0 ..< min(frame.count, 1920) {
                    mixedFrame[i] += Int32(frame[i])
                }
            } else {
                finishedIds.append(id)
                activeSourcesFinished += 1
            }
        }

        if !finishedIds.isEmpty {
            sourcesLock.write { currentSources in
                currentSources.removeAll { finishedIds.contains($0.id) }
            }
        }

        if activeSourcesFinished == activeSources.count, !activeSources.isEmpty {
            return nil
        }

        // clamp down to 16bit so the audio doesn't blast ears
        var finalFrame = [Int16](repeating: 0, count: 1920)
        for i in 0 ..< 1920 {
            let sample = mixedFrame[i]
            if sample > Int32(Int16.max) {
                finalFrame[i] = Int16.max
            } else if sample < Int32(Int16.min) {
                finalFrame[i] = Int16.min
            } else {
                finalFrame[i] = Int16(sample)
            }
        }
        return finalFrame
    }
}
