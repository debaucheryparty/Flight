import Foundation

final class HeartbeatManager: Sendable {
    private let intervalMs: Double
    private let sendHeartbeat: @Sendable (Int) -> Void
    private let onTimeout: @Sendable () -> Void
    private let logger: Logger

    private let state = Protected(HeartbeatState())

    private struct HeartbeatState {
        var sequence = 0
        var ackPending = false
        var task: Task<Void, Never>?
    }

    init(
        intervalMs: Double,
        sendHeartbeat: @escaping @Sendable (Int) -> Void,
        onTimeout: @escaping @Sendable () -> Void,
        logger: Logger
    ) {
        self.intervalMs = intervalMs
        self.sendHeartbeat = sendHeartbeat
        self.onTimeout = onTimeout
        self.logger = logger
    }

    func start() {
        stop()

        let task = Task { [weak self] in
            guard let self else { return }

            let jitter = Double.random(in: 0.0 ... 1.0)
            let initialDelay = intervalMs * jitter

            do {
                try await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000))
            } catch {
                return
            }

            while !Task.isCancelled {
                let currentSequence = state.write { s -> Int in
                    if s.ackPending {
                        return -1
                    }

                    s.sequence += 1
                    s.ackPending = true
                    return s.sequence
                }

                if currentSequence == -1 {
                    logger.error("Zombie connection detected: missed heartbeat ACK")
                    onTimeout()
                    break
                }

                logger.debug("Sending heartbeat sequence \(currentSequence)")
                sendHeartbeat(currentSequence)

                do {
                    try await Task.sleep(nanoseconds: UInt64(intervalMs * 1_000_000))
                } catch {
                    break
                }
            }
        }

        state.write { s in
            s.task = task
            s.ackPending = false
        }
    }

    func stop() {
        let taskToCancel = state.write { s -> Task<Void, Never>? in
            let t = s.task
            s.task = nil
            s.ackPending = false
            return t
        }
        taskToCancel?.cancel()
    }

    func receiveAck(sequence: Int) {
        state.write { s in
            if s.sequence == sequence {
                s.ackPending = false
                logger.debug("Received heartbeat ACK \(sequence)")
            } else {
                logger.warning("Heartbeat ACK sequence mismatch: expected \(s.sequence), got \(sequence)")
            }
        }
    }
}
