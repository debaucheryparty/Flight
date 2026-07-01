import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket

final class WebSocketClient: @unchecked Sendable {
    enum Event {
        case text(String)
        case binary(ByteBuffer)
        case close(UInt16, String?)
        case error(Error)
    }

    private let host: String
    private let port: Int
    private let path: String
    private let onEvent: @Sendable (Event) -> Void
    private let logger: Logger

    private let channelLock = Protected<Channel?>(nil)

    init(
        host: String,
        port: Int = 443,
        path: String,
        logger: Logger,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.host = host
        self.port = port
        self.path = path
        self.logger = logger
        self.onEvent = onEvent
    }

    func connect() async throws {
        let eventLoop = EventLoopProvider.sharedGroup.next()
        let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
        let upgradePromise = eventLoop.makePromise(of: Void.self)

        let randomBytes = (0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) }
        let secWebSocketKey = Data(randomBytes).base64EncodedString()

        defer {
            upgradePromise.fail(VoiceError.connectionTimeout)
        }

        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                    try channel.pipeline.syncOperations.addHandler(sslHandler)

                    let upgrader = NIOWebSocketClientUpgrader(
                        requestKey: secWebSocketKey,
                        maxFrameSize: 1 << 16,
                        automaticErrorHandling: true
                    ) { channel, _ in
                        let frameHandler = WebSocketFrameHandler(onEvent: self.onEvent, logger: self.logger, client: self)
                        return channel.pipeline.addHandler(frameHandler).map {
                            upgradePromise.succeed(())
                        }
                    }

                    let config = NIOHTTPClientUpgradeConfiguration(
                        upgraders: [upgrader],
                        completionHandler: { _ in }
                    )

                    try channel.pipeline.syncOperations.addHTTPClientHandlers(
                        leftOverBytesStrategy: .forwardBytes,
                        withClientUpgrade: config
                    )
                }
            }

        logger.trace("Connecting TCP socket to \(host):\(port)...")
        let channel = try await bootstrap.connect(host: host, port: port).get()
        channelLock.write { $0 = channel }
        logger.trace("TCP socket connected! Sending HTTP upgrade request to \(path)...")

        var requestHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: path
        )
        requestHead.headers.add(name: "Host", value: host)
        requestHead.headers.add(name: "User-Agent", value: "DiscordBot (https://github.com/apple/swift-nio, 1.0.0)")

        channel.write(HTTPClientRequestPart.head(requestHead), promise: nil)
        try await channel.writeAndFlush(HTTPClientRequestPart.end(nil))
        logger.trace("HTTP upgrade request sent. Waiting for WSS handshake response...")

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            upgradePromise.fail(VoiceError.connectionTimeout)
        }

        do {
            try await upgradePromise.futureResult.get()
            timeoutTask.cancel()
            logger.debug("WebSocket handshake completed successfully")
        } catch {
            timeoutTask.cancel()
            logger.error("WebSocket handshake failed: \(error)")
            _ = try? await channel.close()
            channelLock.write { $0 = nil }
            throw error
        }
    }

    func send(text: String) async throws {
        logger.trace("Writing text frame: \(text)")
        guard let channel = channelLock.read({ $0 }), channel.isActive else {
            throw VoiceError.webSocketClosed(1006, "Connection lost")
        }
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)

        let randomBytes = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        let maskingKey = WebSocketMaskingKey(randomBytes)!

        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: maskingKey, data: buffer)
        try await channel.writeAndFlush(frame)
    }

    func send(binary data: Data) async throws {
        logger.trace("Writing binary frame: \(data.count) bytes")
        guard let channel = channelLock.read({ $0 }), channel.isActive else {
            throw VoiceError.webSocketClosed(1006, "Connection lost")
        }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        let randomBytes = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        let maskingKey = WebSocketMaskingKey(randomBytes)!

        let frame = WebSocketFrame(fin: true, opcode: .binary, maskKey: maskingKey, data: buffer)
        try await channel.writeAndFlush(frame)
    }

    private let closingIntentionally = Protected<Bool>(false)

    var isClosingIntentionally: Bool {
        closingIntentionally.read { $0 }
    }

    func close(code: UInt16 = 1000) async throws {
        closingIntentionally.write { $0 = true }
        guard let channel = channelLock.read({ $0 }), channel.isActive else { return }
        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.writeInteger(code)

        let randomBytes = (0 ..< 4).map { _ in UInt8.random(in: 0 ... 255) }
        let maskingKey = WebSocketMaskingKey(randomBytes)!

        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: maskingKey, data: buffer)
        try? await channel.writeAndFlush(frame)
        try? await channel.close()
        channelLock.write { $0 = nil }
    }
}

private final class WebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let onEvent: @Sendable (WebSocketClient.Event) -> Void
    private let logger: Logger
    private let closed = Protected<Bool>(false)
    private weak var client: WebSocketClient?

    init(onEvent: @escaping @Sendable (WebSocketClient.Event) -> Void, logger: Logger, client: WebSocketClient) {
        self.onEvent = onEvent
        self.logger = logger
        self.client = client
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        logger.trace("WebSocketFrameHandler read frame with opcode: \(frame.opcode)")

        switch frame.opcode {
        case .text:
            var data = frame.unmaskedData
            if let text = data.readString(length: data.readableBytes) {
                logger.trace("Read text frame: \(text)")
                onEvent(.text(text))
            }
        case .binary:
            onEvent(.binary(frame.unmaskedData))
        case .connectionClose:
            let isAlreadyClosed = closed.write { wasClosed -> Bool in
                if wasClosed { return true }
                wasClosed = true
                return false
            }
            if isAlreadyClosed { return }

            var data = frame.unmaskedData
            let code = data.readInteger(as: UInt16.self) ?? 1000
            let reason = data.readString(length: data.readableBytes)
            onEvent(.close(code, reason))
            context.close(promise: nil as EventLoopPromise<Void>?)
        case .ping:
            let data = frame.unmaskedData
            let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: data)
            context.writeAndFlush(wrapOutboundOut(pongFrame), promise: nil as EventLoopPromise<Void>?)
        case .pong:
            break
        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if client?.isClosingIntentionally == true {
            logger.trace("Suppressed error during intentional close: \(error)")
            return
        }
        logger.warning("WebSocket error: \(error)")
        let isAlreadyClosed = closed.write { wasClosed -> Bool in
            if wasClosed { return true }
            wasClosed = true
            return false
        }
        if !isAlreadyClosed {
            onEvent(.error(error))
            context.close(promise: nil as EventLoopPromise<Void>?)
        }
    }

    func channelInactive(context _: ChannelHandlerContext) {
        if client?.isClosingIntentionally == true {
            logger.trace("Channel inactive during intentional close")
            return
        }
        logger.trace("Channel inactive")
        let isAlreadyClosed = closed.write { wasClosed -> Bool in
            if wasClosed { return true }
            wasClosed = true
            return false
        }
        if !isAlreadyClosed {
            onEvent(.close(1006, "Channel became inactive"))
        }
    }
}
