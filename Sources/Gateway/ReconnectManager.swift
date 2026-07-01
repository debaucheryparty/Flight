import Foundation

final class ReconnectManager: Sendable {
    private let config: FlightConfiguration
    private let state = Protected(ReconnectState())
    private let logger: Logger

    private struct ReconnectState {
        var attempts = 0
        var stableTimerTask: Task<Void, Never>?
    }

    init(config: FlightConfiguration, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func nextDelay() -> Double {
        let attempts = state.write { s -> Int in
            s.attempts += 1
            return s.attempts
        }

        let exponent = min(attempts - 1, 10)
        let baseDelay = config.baseReconnectDelay * pow(2.0, Double(exponent))
        let cappedDelay = min(baseDelay, config.maxReconnectDelay)

        let jitter = Double.random(in: 0.0 ... config.reconnectJitter)
        let totalDelay = cappedDelay + jitter

        logger.info("Scheduling reconnect attempt #\(attempts) in \(String(format: "%.2f", totalDelay)) seconds")
        return totalDelay
    }

    func connectionSucceeded() {
        state.write { s in
            s.stableTimerTask?.cancel()
            s.stableTimerTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    self?.reset()
                } catch {}
            }
        }
    }

    func reset() {
        state.write { s in
            if s.attempts > 0 {
                logger.debug("Connection verified stable. Resetting reconnect attempts.")
            }
            s.attempts = 0
            s.stableTimerTask?.cancel()
            s.stableTimerTask = nil
        }
    }

    func stop() {
        state.write { s in
            s.stableTimerTask?.cancel()
            s.stableTimerTask = nil
        }
    }
}
