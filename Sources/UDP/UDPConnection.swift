import Foundation
import NIOCore
import NIOPosix

final class UDPConnection: @unchecked Sendable {
    private let logger: Logger
    let stateMachine = AsyncState<UDPState>(.idle)

    private let channelLock = Protected<Channel?>(nil)
    private let remoteAddressLock = Protected<SocketAddress?>(nil)

    private struct DiscoveryState {
        var continuation: CheckedContinuation<(ip: String, port: UInt16), Error>?
        var retryTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var expectedSSRC: UInt32?
    }

    private let discoveryLock = Protected<DiscoveryState>(DiscoveryState())

    init(logger: Logger) {
        self.logger = logger
    }

    var state: UDPState {
        stateMachine.current
    }

    func connect(host: String, port: UInt16) async throws {
        await close()

        stateMachine.transition(to: .connecting)
        let eventLoop = EventLoopProvider.sharedGroup.next()

        let bootstrap = DatagramBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { [weak self] channel in
                channel.eventLoop.makeCompletedFuture {
                    guard let self else { return }
                    let handler = UDPFrameHandler(logger: self.logger) { [weak self] bytes in
                        self?.handleIncomingMessage(bytes)
                    }
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }

        do {
            let channel = try await bootstrap.connect(host: host, port: Int(port)).get()
            guard let remoteAddress = channel.remoteAddress else {
                throw VoiceError.handshakeFailed("Could not resolve remote address for \(host):\(port)")
            }
            channelLock.write { $0 = channel }
            remoteAddressLock.write { $0 = remoteAddress }
            logger.info("UDP socket connected to \(remoteAddress)")
        } catch {
            logger.error("Failed to connect UDP socket to \(host):\(port) - \(error)")
            stateMachine.transition(to: .idle)
            throw error
        }
    }

    func discoverIP(ssrc: UInt32, timeout: TimeInterval = 2.0) async throws -> (ip: String, port: UInt16) {
        guard stateMachine.current == .connecting || stateMachine.current == .ready else {
            throw VoiceError.handshakeFailed("UDP connection is not active")
        }

        stateMachine.transition(to: .discovering)

        return try await withCheckedThrowingContinuation { continuation in
            discoveryLock.write { state in
                state.expectedSSRC = ssrc
                state.continuation = continuation

                self.sendDiscoveryRequest(ssrc: ssrc)

                let retryTask = Task { [weak self] in
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: 200_000_000)
                        } catch {
                            break
                        }
                        self?.sendDiscoveryRequest(ssrc: ssrc)
                    }
                }
                state.retryTask = retryTask

                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    } catch {
                        return
                    }

                    self?.handleDiscoveryTimeout()
                }
                state.timeoutTask = timeoutTask
            }
        }
    }

    private func sendDiscoveryRequest(ssrc: UInt32) {
        guard let channel = channelLock.read({ $0 }),
              let remoteAddress = remoteAddressLock.read({ $0 }) else { return }

        let requestBytes = Discovery.makeRequest(ssrc: ssrc)
        var buffer = channel.allocator.buffer(capacity: requestBytes.count)
        buffer.writeBytes(requestBytes)

        let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)

        logger.debug("Transmitting UDP discovery request (SSRC: \(ssrc))")
        channel.writeAndFlush(envelope, promise: nil)
    }

    private func handleDiscoveryTimeout() {
        let (continuation, retryTask) = discoveryLock.write { state -> (CheckedContinuation<(ip: String, port: UInt16), Error>?, Task<Void, Never>?) in
            let c = state.continuation
            let r = state.retryTask
            state.continuation = nil
            state.retryTask = nil
            state.timeoutTask = nil
            state.expectedSSRC = nil
            return (c, r)
        }

        retryTask?.cancel()

        if let continuation {
            logger.error("UDP IP discovery timed out")
            continuation.resume(throwing: VoiceError.connectionTimeout)
        }

        Task {
            await self.close()
        }
    }

    var onAudioPacket: (@Sendable ([UInt8]) -> Void)?

    private func handleIncomingMessage(_ bytes: [UInt8]) {
        let expectedSSRC = discoveryLock.read { $0.expectedSSRC }
        guard let expectedSSRC else {
            onAudioPacket?(bytes)
            return
        }

        if bytes.count != 74 {
            onAudioPacket?(bytes)
            return
        }

        do {
            let (ip, port) = try Discovery.parseResponse(bytes: bytes, expectedSSRC: expectedSSRC)

            let (continuation, retryTask, timeoutTask) = discoveryLock.write { state -> (CheckedContinuation<(ip: String, port: UInt16), Error>?, Task<Void, Never>?, Task<Void, Never>?) in
                let c = state.continuation
                let r = state.retryTask
                let t = state.timeoutTask
                state.continuation = nil
                state.retryTask = nil
                state.timeoutTask = nil
                state.expectedSSRC = nil
                return (c, r, t)
            }

            retryTask?.cancel()
            timeoutTask?.cancel()

            if let continuation {
                logger.info("UDP IP discovery completed successfully: \(ip):\(port)")
                stateMachine.transition(to: .ready)
                continuation.resume(returning: (ip, port))
            }
        } catch {
            let (continuation, retryTask, timeoutTask) = discoveryLock.write { state -> (CheckedContinuation<(ip: String, port: UInt16), Error>?, Task<Void, Never>?, Task<Void, Never>?) in
                let c = state.continuation
                let r = state.retryTask
                let t = state.timeoutTask
                state.continuation = nil
                state.retryTask = nil
                state.timeoutTask = nil
                state.expectedSSRC = nil
                return (c, r, t)
            }

            retryTask?.cancel()
            timeoutTask?.cancel()

            if let continuation {
                logger.error("UDP IP discovery failed due to malformed packet: \(error)")
                stateMachine.transition(to: .idle)
                continuation.resume(throwing: error)
            }

            Task {
                await self.close()
            }
        }
    }

    func close() async {
        logger.info("Closing UDP connection")
        stateMachine.transition(to: .idle)

        let (continuation, retryTask, timeoutTask) = discoveryLock.write { state -> (CheckedContinuation<(ip: String, port: UInt16), Error>?, Task<Void, Never>?, Task<Void, Never>?) in
            let c = state.continuation
            let r = state.retryTask
            let t = state.timeoutTask
            state.continuation = nil
            state.retryTask = nil
            state.timeoutTask = nil
            state.expectedSSRC = nil
            return (c, r, t)
        }

        retryTask?.cancel()
        timeoutTask?.cancel()

        if let continuation {
            continuation.resume(throwing: VoiceError.webSocketClosed(1006, "UDP socket closed during IP discovery"))
        }

        let channel = channelLock.write { old -> Channel? in
            let temp = old
            old = nil
            return temp
        }

        remoteAddressLock.write { $0 = nil }

        if let channel {
            try? await channel.close()
        }
    }

    func send(bytes: [UInt8]) throws {
        guard let channel = channelLock.read({ $0 }),
              let remoteAddress = remoteAddressLock.read({ $0 }),
              stateMachine.current == .ready
        else {
            throw VoiceError.webSocketClosed(1006, "UDP connection is not active or ready")
        }

        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)

        let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)
        channel.writeAndFlush(envelope, promise: nil)
    }
}

private final class UDPFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let onMessage: @Sendable ([UInt8]) -> Void
    private let logger: Logger

    init(logger: Logger, onMessage: @escaping @Sendable ([UInt8]) -> Void) {
        self.logger = logger
        self.onMessage = onMessage
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            onMessage(bytes)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("UDP handler error: \(error)")
        context.close(promise: nil)
    }
}
