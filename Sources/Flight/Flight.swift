import Foundation

public enum Flight {
    public static let version = "0.1.0"

    public static var maxDaveProtocolVersion: UInt16 {
        DaveSessionManager.maxSupportedProtocolVersion()
    }
}

public final class VoiceClient: @unchecked Sendable {
    public var onReady: (@Sendable (_ ssrc: UInt32) -> Void)?

    public var onError: (@Sendable (_ error: Error) -> Void)?

    public var onUserConnect: (@Sendable (_ userIds: [String]) -> Void)?

    public var onUserDisconnect: (@Sendable (_ userId: String) -> Void)?

    public var onAudioReceived: (@Sendable (_ userId: String, _ pcm: [Int16]) -> Void)?

    public var onStateChange: (@Sendable (_ state: ConnectionState) -> Void)?

    public enum ConnectionState: String, Sendable {
        case disconnected
        case connecting
        case identifying
        case discovering
        case negotiating
        case ready
        case reconnecting
    }

    private let logger = Logger(label: "Flight.VoiceClient")
    private let gateway: VoiceGateway
    private let ssrcLock = Protected<UInt32?>(nil)
    private let transporterLock = Protected<VoiceTransporter?>(nil)
    private let receiverLock = Protected<VoiceReceiver?>(nil)
    private let udpLock = Protected<UDPConnection?>(nil)
    private let encryptionLock = Protected<VoiceEncryption?>(nil)

    public init() {
        gateway = VoiceGateway()
        setupEventHandling()
    }

    public func connect(
        serverId: String,
        userId: String,
        sessionId: String,
        token: String,
        endpoint: String
    ) async throws {
        let session = GatewaySession(
            serverId: serverId,
            userId: userId,
            sessionId: sessionId,
            token: token,
            endpoint: endpoint
        )
        try await gateway.connect(session: session)
    }

    public func updateServer(token: String, endpoint: String) async throws {
        try await gateway.updateServer(endpoint: endpoint, token: token)
    }

    public func disconnect() async {
        await gateway.disconnect()
        transporterLock.write { $0 = nil }
        ssrcLock.write { $0 = nil }
        udpLock.write { $0 = nil }
        encryptionLock.write { $0 = nil }
    }

    public var isReady: Bool {
        gateway.isReadyState && ssrcLock.read { $0 } != nil
    }

    public func sendOpusFrame(_ opusData: [UInt8]) async throws {
        guard let transporter = transporterLock.read({ $0 }),
              let encryption = encryptionLock.read({ $0 }),
              let udp = udpLock.read({ $0 })
        else {
            throw VoiceError.webSocketClosed(1006, "Not connected or not ready")
        }

        try await transporter.sendFrame(
            opusData,
            encryption: encryption,
            udp: udp,
            daveSessionManager: gateway.daveSessionManager
        )
    }

    public func sendAudio(pcm: [Int16], frameSize: Int, encoder: OpusEncoder) async throws {
        let opusData = try encoder.encode(pcm: pcm, frameSize: frameSize)
        try await sendOpusFrame(opusData)
    }

    public func startSpeaking() async throws {
        guard let transporter = transporterLock.read({ $0 }) else { return }
        try await transporter.startSpeaking()
    }

    public func stopSpeaking() async throws {
        guard let transporter = transporterLock.read({ $0 }) else { return }
        try await transporter.stopSpeaking()
    }

    private func setupEventHandling() {
        gateway.onEvent = { [weak self] event in
            self?.handleGatewayEvent(event)
        }
    }

    private func handleGatewayEvent(_ event: GatewayEvent) {
        switch event {
        case let .ready(ready):
            ssrcLock.write { $0 = ready.ssrc }
            onStateChange?(.discovering)

        case .sessionDescription:
            guard let ssrc = ssrcLock.read({ $0 }),
                  let udp = gateway.udpConnection,
                  let encryption = gateway.voiceEncryption else { return }

            let transporter = VoiceTransporter(gateway: gateway, ssrc: ssrc)
            transporterLock.write { $0 = transporter }

            let receiver = VoiceReceiver(
                gateway: gateway,
                encryption: encryption,
                daveSessionManager: gateway.daveSessionManager
            )
            receiver.onAudioReceived = { [weak self] userId, pcm in
                self?.onAudioReceived?(userId, pcm)
            }
            receiverLock.write { $0 = receiver }

            udp.onAudioPacket = { [weak receiver] bytes in
                receiver?.handleIncomingPacket(bytes)
            }

            udpLock.write { $0 = udp }
            encryptionLock.write { $0 = encryption }

            onStateChange?(.ready)
            onReady?(ssrc)

        case let .clientConnect(payload):
            onUserConnect?(payload.user_ids)

        case let .clientDisconnect(payload):
            receiverLock.read { $0 }?.removeUser(userId: payload.user_id)
            onUserDisconnect?(payload.user_id)

        case .resumed:
            onStateChange?(.ready)

        case .close:
            onStateChange?(.disconnected)

        case let .error(error):
            onError?(error)

        default:
            break
        }
    }
}
