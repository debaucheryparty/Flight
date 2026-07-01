import Foundation

actor JitterBuffer {
    private let ssrc: UInt32
    private let logger: Logger

    private let bufferDepth: Int
    private let frameDurationNs: UInt64 = 20_000_000

    private struct BufferedPacket {
        let sequence: UInt16
        let timestamp: UInt32
        let payload: [UInt8]
    }

    private var buffer: [BufferedPacket] = []

    private var expectedSequence: UInt16?
    private var isBuffering = true

    private var dispatchTask: Task<Void, Never>?

    var onFrameReady: (@Sendable ([UInt8]) -> Void)?

    init(ssrc: UInt32, bufferDepth: Int = 2, logger: Logger = Logger(label: "Flight.JitterBuffer")) {
        self.ssrc = ssrc
        self.bufferDepth = bufferDepth
        self.logger = logger
    }

    func setOnFrameReady(_ callback: @escaping @Sendable ([UInt8]) -> Void) {
        onFrameReady = callback
    }

    deinit {
        dispatchTask?.cancel()
    }

    func push(sequence: UInt16, timestamp: UInt32, payload: [UInt8]) {
        buffer.append(BufferedPacket(sequence: sequence, timestamp: timestamp, payload: payload))
        // sort by sequence so they play back in right order
        buffer.sort { diff(seq1: $0.sequence, seq2: $1.sequence) < 0 }

        if isBuffering, buffer.count >= bufferDepth {
            isBuffering = false
            expectedSequence = buffer.first?.sequence
            startDispatchLoop()
        }
    }

    func stop() {
        dispatchTask?.cancel()
        dispatchTask = nil
        buffer.removeAll()
        isBuffering = true
        expectedSequence = nil
    }

    private func startDispatchLoop() {
        dispatchTask?.cancel()

        let clock = ContinuousClock()
        let duration = Duration.nanoseconds(frameDurationNs)

        dispatchTask = Task {
            var nextSendTime = clock.now + duration
            while !Task.isCancelled {
                do {
                    // sleep strictly 20ms between each frame
                    try await Task.sleep(until: nextSendTime, clock: clock)
                } catch {
                    break
                }
                if Task.isCancelled { break }

                dispatchNextFrame()
                nextSendTime += duration
            }
        }
    }

    private func dispatchNextFrame() {
        guard let expected = expectedSequence else { return }

        if let idx = buffer.firstIndex(where: { $0.sequence == expected }) {
            let packet = buffer.remove(at: idx)
            onFrameReady?(packet.payload)
        } else {
            // missing packet so send empty array to trigger plc in opus
            onFrameReady?([])
        }

        buffer.removeAll { diff(seq1: $0.sequence, seq2: expected) < 0 }

        expectedSequence = expected &+ 1

        if buffer.count > bufferDepth * 5 {
            logger.warning("Jitter buffer overflow for SSRC \(ssrc). Resetting.")
            stop()
        }
    }

    private func diff(seq1: UInt16, seq2: UInt16) -> Int16 {
        return Int16(bitPattern: seq1 &- seq2)
    }
}
