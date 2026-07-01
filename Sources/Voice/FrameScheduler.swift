import Foundation

final class FrameScheduler: Sendable {
    private let tickDuration: Duration
    private let onTick: @Sendable () async throws -> Void

    private let running = Protected<Bool>(false)
    private let task = Protected<Task<Void, Never>?>(nil)

    init(tickMs: Int = 20, onTick: @escaping @Sendable () async throws -> Void) {
        tickDuration = .milliseconds(tickMs)
        self.onTick = onTick
    }

    func start() {
        running.write { $0 = true }

        let clock = ContinuousClock()
        let duration = tickDuration
        let tickCallback = onTick

        let schedulerTask = Task { [weak self] in
            var nextSendTime = clock.now

            while !Task.isCancelled {
                guard let self, self.running.read({ $0 }) else { break }

                do {
                    try await tickCallback()
                } catch {
                    print("FrameScheduler tick failed: \(error)")
                }

                nextSendTime = nextSendTime + duration

                let now = clock.now
                if now < nextSendTime {
                    do {
                        try await Task.sleep(until: nextSendTime, clock: clock)
                    } catch {
                        break
                    }
                } else {
                    nextSendTime = now
                }
            }
        }

        task.write { $0 = schedulerTask }
    }

    func stop() {
        running.write { $0 = false }
        let activeTask = task.write { old -> Task<Void, Never>? in
            let temp = old
            old = nil
            return temp
        }
        activeTask?.cancel()
    }
}
