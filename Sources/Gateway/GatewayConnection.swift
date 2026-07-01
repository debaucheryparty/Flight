import Foundation
import NIOCore

class GatewayConnection: @unchecked Sendable {
    private let onEvent: @Sendable (GatewayEvent) -> Void
    private let logger: Logger

    private let clientLock = Protected<WebSocketClient?>(nil)

    init(logger: Logger, onEvent: @escaping @Sendable (GatewayEvent) -> Void) {
        self.logger = logger
        self.onEvent = onEvent
    }

    func connect(host: String, version: Int) async throws {
        let cleanHost: String
        let port: Int
        if let colonIndex = host.firstIndex(of: ":") {
            cleanHost = String(host[..<colonIndex])
            port = Int(host[host.index(after: colonIndex)...]) ?? 443
        } else {
            cleanHost = host
            port = 443
        }

        let query = GatewayVersion.queryParameter(for: version)
        let path = "/?\(query)"

        logger.debug("Connecting to Voice Gateway wss://\(cleanHost):\(port)\(path)")

        let client = WebSocketClient(host: cleanHost, port: port, path: path, logger: logger) { [weak self] event in
            self?.handleWebSocketEvent(event)
        }

        clientLock.write { $0 = client }
        try await client.connect()
    }

    func send(op: GatewayOpcode, data: some Codable & Sendable) async throws {
        guard let client = clientLock.read({ $0 }) else {
            throw VoiceError.webSocketClosed(1006, "Connection not established")
        }

        let payload = OutgoingContainer(op: op.rawValue, d: data)
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(payload)

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw VoiceError.invalidPayload
        }

        try await client.send(text: jsonString)
    }

    func sendBinary(op: GatewayOpcode, payload: Data) async throws {
        guard let client = clientLock.read({ $0 }) else {
            throw VoiceError.webSocketClosed(1006, "Connection not established")
        }

        var frame = Data(capacity: 1 + payload.count)

        frame.append(UInt8(op.rawValue))

        frame.append(payload)

        try await client.send(binary: frame)
    }

    func close(code: UInt16 = 1000) async throws {
        let client = clientLock.write { old -> WebSocketClient? in
            let c = old
            old = nil
            return c
        }
        try await client?.close(code: code)
    }

    private func handleWebSocketEvent(_ event: WebSocketClient.Event) {
        switch event {
        case let .text(text):
            parseAndEmit(text)
        case let .binary(data):
            let bytes = Array(data.readableBytesView)
            guard bytes.count >= 3 else {
                logger.warning("Received binary frame too small")
                return
            }

            let opcode = bytes[2]
            let payloadBytes = bytes[3...]
            let payloadData = Data(payloadBytes)

            switch opcode {
            case 25:
                logger.info("DAVE: Received MLS_EXTERNAL_SENDER_PACKAGE (\(payloadData.count) bytes)")
                onEvent(.mlsExternalSenderPackage(MlsExternalSenderPackagePayload(data: payloadData)))

            case 27:
                logger.info("DAVE: Received MLS_PROPOSALS (\(payloadData.count) bytes)")
                onEvent(.mlsProposals(MlsProposalsPayload(data: payloadData)))

            case 29:
                if payloadBytes.count >= 2 {
                    let transitionId = (UInt16(payloadBytes[payloadBytes.startIndex]) << 8) | UInt16(payloadBytes[payloadBytes.startIndex + 1])
                    let commitData = Data(payloadBytes.dropFirst(2))
                    logger.info("DAVE: Received MLS_PREPARE_COMMIT_TRANSITION (ID: \(transitionId), \(commitData.count) bytes)")
                    onEvent(.mlsPrepareCommitTransition(MlsPrepareCommitTransitionPayload(transitionId: transitionId, data: commitData)))
                }

            case 30:
                if payloadBytes.count >= 2 {
                    let transitionId = (UInt16(payloadBytes[payloadBytes.startIndex]) << 8) | UInt16(payloadBytes[payloadBytes.startIndex + 1])
                    let welcomeData = Data(payloadBytes.dropFirst(2))
                    logger.info("DAVE: Received MLS_WELCOME (ID: \(transitionId), \(welcomeData.count) bytes)")
                    onEvent(.mlsWelcome(MlsWelcomePayload(transitionId: transitionId, data: welcomeData)))
                }

            default:
                logger.warning("Received unhandled binary opcode \(opcode)")
            }
        case let .close(code, reason):
            onEvent(.close(GatewayClose(code: code, reason: reason)))
        case let .error(error):
            onEvent(.error(error))
        }
    }

    private func parseAndEmit(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            onEvent(.error(VoiceError.invalidPayload))
            return
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let opRaw = json?["op"] as? Int,
                  let op = GatewayOpcode(rawValue: opRaw)
            else {
                logger.warning("Voice Gateway payload has invalid or missing opcode")
                return
            }

            let decoder = JSONDecoder()

            switch op {
            case .hello:
                struct HelloContainer: Codable { let d: HelloPayload }
                let container = try decoder.decode(HelloContainer.self, from: data)
                onEvent(.hello(container.d))

            case .ready:
                struct ReadyContainer: Codable { let d: ReadyPayload }
                let container = try decoder.decode(ReadyContainer.self, from: data)
                onEvent(.ready(container.d))

            case .resumed:
                onEvent(.resumed)

            case .sessionDescription:
                struct DescContainer: Codable { let d: SessionDescriptionPayload }
                let container = try decoder.decode(DescContainer.self, from: data)
                onEvent(.sessionDescription(container.d))

            case .speaking:
                struct SpeakingContainer: Codable { let d: SpeakingPayload }
                let container = try decoder.decode(SpeakingContainer.self, from: data)
                onEvent(.speaking(container.d))

            case .clientConnect:
                struct ClientConnectContainer: Codable { let d: ClientConnectPayload }
                let container = try decoder.decode(ClientConnectContainer.self, from: data)
                onEvent(.clientConnect(container.d))

            case .clientDisconnect:
                struct ClientDisconnectContainer: Codable { let d: ClientDisconnectPayload }
                let container = try decoder.decode(ClientDisconnectContainer.self, from: data)
                onEvent(.clientDisconnect(container.d))

            case .clientFlags:
                struct ClientFlagsContainer: Codable { let d: ClientFlagsPayload }
                let container = try decoder.decode(ClientFlagsContainer.self, from: data)
                onEvent(.clientFlags(container.d))

            case .clientPlatform:
                struct ClientPlatformContainer: Codable { let d: ClientPlatformPayload }
                let container = try decoder.decode(ClientPlatformContainer.self, from: data)
                onEvent(.clientPlatform(container.d))

            case .heartbeatAck:
                struct AckContainer: Codable { let d: HeartbeatAckPayload }
                let container = try JSONDecoder().decode(AckContainer.self, from: data)
                onEvent(.heartbeatAck(container.d.t))

            case .davePrepareTransition:
                struct DavePrepareContainer: Codable { let d: DavePrepareTransitionPayload }
                let container = try decoder.decode(DavePrepareContainer.self, from: data)
                onEvent(.davePrepareTransition(container.d))

            case .daveExecuteTransition:
                struct DaveExecuteContainer: Codable { let d: DaveExecuteTransitionPayload }
                let container = try decoder.decode(DaveExecuteContainer.self, from: data)
                onEvent(.daveExecuteTransition(container.d))

            case .davePrepareEpoch:
                struct DaveEpochContainer: Codable { let d: DavePrepareEpochPayload }
                let container = try decoder.decode(DaveEpochContainer.self, from: data)
                onEvent(.davePrepareEpoch(container.d))

            case .mlsExternalSenderPackage, .mlsProposals, .mlsPrepareCommitTransition, .mlsWelcome:
                logger.warning("Received MLS opcode \(op.rawValue) as text frame — expected binary")

            default:
                logger.debug("Received unhandled opcode \(op.rawValue)")
            }
        } catch {
            logger.error("Failed to decode gateway payload: \(error)")
            onEvent(.error(error))
        }
    }
}

private struct OutgoingContainer<D: Codable>: Codable {
    let op: Int
    let d: D
}
