import Foundation

public final class VoiceGateway: @unchecked Sendable {
    private let config: FlightConfiguration
    private let logger: Logger

    let stateMachine = AsyncState<GatewayState>(.disconnected)
    private let reconnectManager: ReconnectManager

    let sessionLock = Protected<GatewaySession?>(nil)
    let connectionLock = Protected<GatewayConnection?>(nil)
    private let heartbeatLock = Protected<HeartbeatManager?>(nil)
    private let isResumePending = Protected<Bool>(false)
    private let connectionGeneration = Protected<Int>(0)
    private let udpConnectionLock = Protected<UDPConnection?>(nil)
    private let voiceEncryptionLock = Protected<VoiceEncryption?>(nil)

    let daveSessionManagerLock = Protected<DaveSessionManager?>(nil)

    let ssrcToUserIdLock = Protected<[UInt32: String]>([:])

    private let ssrcLock = Protected<UInt32?>(nil)
    var ssrc: UInt32? {
        ssrcLock.read { $0 }
    }

    private struct GatewayTasks {
        var reconnect: Task<Void, Never>? = nil
        var handshake: Task<Void, Never>? = nil
    }

    private let tasksLock = Protected<GatewayTasks>(GatewayTasks())

    var onEvent: (@Sendable (GatewayEvent) -> Void)?

    init(
        config: FlightConfiguration = FlightConfiguration(),
        logger: Logger = Logger(label: "Flight.VoiceGateway")
    ) {
        self.config = config
        self.logger = logger
        reconnectManager = ReconnectManager(config: config, logger: logger)
    }

    var state: GatewayState {
        stateMachine.current
    }

    var isReadyState: Bool {
        stateMachine.current == .ready
    }

    var udpConnection: UDPConnection? {
        udpConnectionLock.read { $0 }
    }

    var voiceEncryption: VoiceEncryption? {
        voiceEncryptionLock.read { $0 }
    }

    var daveSessionManager: DaveSessionManager? {
        daveSessionManagerLock.read { $0 }
    }

    func connect(session: GatewaySession) async throws {
        await disconnect()

        sessionLock.write { $0 = session }
        isResumePending.write { $0 = false }
        stateMachine.transition(to: .connecting)

        try await performConnect()
    }

    private func performConnect() async throws {
        guard let session = sessionLock.read({ $0 }) else {
            throw VoiceError.missingCredentials
        }

        _ = connectionGeneration.write { gen -> Int in
            gen += 1
            return gen
        }

        let connection = GatewayConnection(logger: logger) { [weak self] event in
            self?.handleEvent(event)
        }

        connectionLock.write { $0 = connection }

        do {
            try await connection.connect(host: session.endpoint, version: config.gatewayVersion)
        } catch {
            logger.error("Failed to connect to gateway at \(session.endpoint): \(error)")
            handleDisconnect(reason: .error(error))
            throw error
        }
    }

    func disconnect() async {
        logger.info("Disconnecting cleanly from Voice Gateway")
        stateMachine.transition(to: .disconnected)

        connectionGeneration.write { $0 += 1 }

        reconnectManager.stop()
        stopHeartbeats()
        cancelAllTasks()
        isResumePending.write { $0 = false }

        let conn = connectionLock.write { old -> GatewayConnection? in
            let temp = old
            old = nil
            return temp
        }
        if let conn {
            try? await conn.close(code: 1000)
        }

        let udp = udpConnectionLock.write { old -> UDPConnection? in
            let temp = old
            old = nil
            return temp
        }
        if let udp {
            await udp.close()
        }

        voiceEncryptionLock.write { $0 = nil }
        ssrcLock.write { $0 = nil }
    }

    func updateServer(endpoint: String, token: String) async throws {
        guard let oldSession = sessionLock.read({ $0 }) else {
            throw VoiceError.missingCredentials
        }

        logger.info("Migrating Voice Gateway to new endpoint: \(endpoint)")
        stateMachine.transition(to: .reconnecting)

        let newSession = oldSession.with(endpoint: endpoint, token: token)
        sessionLock.write { $0 = newSession }

        connectionGeneration.write { $0 += 1 }
        stopHeartbeats()
        cancelAllTasks()

        isResumePending.write { $0 = true }

        let conn = connectionLock.write { old -> GatewayConnection? in
            let temp = old
            old = nil
            return temp
        }
        if let conn {
            try? await conn.close(code: 1000)
        }

        let udp = udpConnectionLock.write { old -> UDPConnection? in
            let temp = old
            old = nil
            return temp
        }
        if let udp {
            await udp.close()
        }

        try await performConnect()
    }

    private func stopHeartbeats() {
        let hb = heartbeatLock.write { old -> HeartbeatManager? in
            let temp = old
            old = nil
            return temp
        }
        hb?.stop()
    }

    private func cancelAllTasks() {
        let tasks = tasksLock.write { t -> (Task<Void, Never>?, Task<Void, Never>?) in
            let r = t.reconnect
            let h = t.handshake
            t.reconnect = nil
            t.handshake = nil
            return (r, h)
        }
        tasks.0?.cancel()
        tasks.1?.cancel()
    }

    func handleEvent(_ event: GatewayEvent) {
        switch event {
        case let .hello(hello):
            logger.debug("Received Hello: scheduling heartbeats (interval: \(hello.heartbeatInterval)ms)")
            startHeartbeats(intervalMs: hello.heartbeatInterval)

            let capturedGen = connectionGeneration.read { $0 }
            let handshakeTask = Task { [weak self] in
                guard let self = self else { return }

                let isCurrentGen = self.connectionGeneration.read { $0 == capturedGen }
                guard isCurrentGen else { return }

                do {
                    let resume = self.isResumePending.read { $0 }
                    if resume {
                        self.stateMachine.transition(to: .identifying)
                        try await self.sendResume()
                    } else {
                        self.stateMachine.transition(to: .identifying)
                        try await self.sendIdentify()
                    }
                } catch {
                    self.logger.error("Failed to transmit handshake payload: \(error)")
                }
            }

            tasksLock.write { $0.handshake = handshakeTask }

        case let .ready(ready):
            ssrcLock.write { $0 = ready.ssrc }
            logger.info("Voice Gateway ready received. SSRC is \(ready.ssrc), server IP: \(ready.ip):\(ready.port)")

            guard let session = sessionLock.read({ $0 }) else { return }
            let daveManager = DaveSessionManager(
                selfUserId: session.userId,
                groupId: UInt64(session.serverId) ?? 0,
                delegate: self
            )
            daveSessionManagerLock.write { $0 = daveManager }

            let capturedGen = connectionGeneration.read { $0 }
            let handshakeTask = Task { [weak self] in
                guard let self = self else { return }

                let isCurrentGen = self.connectionGeneration.read { $0 == capturedGen }
                guard isCurrentGen else { return }

                do {
                    guard let selectedMode = EncryptionMode.selectMode(from: ready.modes) else {
                        throw VoiceError.handshakeFailed("No supported encryption mode found in server-provided list: \(ready.modes)")
                    }
                    self.logger.info("Selected encryption mode: \(selectedMode.rawValue)")

                    self.stateMachine.transition(to: .discovering)

                    let udp = UDPConnection(logger: self.logger)
                    self.udpConnectionLock.write { $0 = udp }

                    try await udp.connect(host: ready.ip, port: ready.port)

                    let (externalIP, externalPort) = try await udp.discoverIP(ssrc: ready.ssrc, timeout: 2.0)

                    self.stateMachine.transition(to: .negotiating)

                    let selectPayload = SelectProtocolPayload(
                        protocolName: "udp",
                        address: externalIP,
                        port: externalPort,
                        mode: selectedMode.rawValue
                    )

                    guard let conn = self.connectionLock.read({ $0 }) else {
                        throw VoiceError.webSocketClosed(1006, "Connection lost during protocol selection")
                    }

                    self.logger.debug("Sending Select Protocol: \(externalIP):\(externalPort) mode: \(selectedMode.rawValue)")
                    try await conn.send(op: .selectProtocol, data: selectPayload)
                } catch {
                    self.logger.error("UDP Handshake / Protocol Selection failed: \(error)")
                    self.handleDisconnect(reason: .error(error))
                }
            }

            tasksLock.write { $0.handshake = handshakeTask }

        case .resumed:
            logger.info("Voice Gateway session successfully resumed")
            stateMachine.transition(to: .ready)
            reconnectManager.connectionSucceeded()

        case let .sessionDescription(desc):
            logger.info("Received session description. Mode: \(desc.mode)")
            guard let encMode = EncryptionMode(rawValue: desc.mode) else {
                logger.error("Unsupported encryption mode received: \(desc.mode)")
                handleDisconnect(reason: .error(VoiceError.handshakeFailed("Unsupported encryption mode: \(desc.mode)")))
                return
            }
            let encryption = VoiceEncryption(secretKey: desc.secretKey, mode: encMode)
            voiceEncryptionLock.write { $0 = encryption }

            if let daveManager = daveSessionManagerLock.read({ $0 }), let protocolVersion = desc.daveProtocolVersion {
                Task {
                    await daveManager.selectProtocol(protocolVersion: UInt16(protocolVersion))
                }
            }

            stateMachine.transition(to: .ready)
            isResumePending.write { $0 = true }
            reconnectManager.connectionSucceeded()

        case let .speaking(speaking):
            if let userId = speaking.user_id {
                ssrcToUserIdLock.write { $0[speaking.ssrc] = userId }
                logger.info("Mapped SSRC \(speaking.ssrc) to user \(userId)")
            }

        case let .heartbeatAck(seq):
            heartbeatLock.read { $0?.receiveAck(sequence: seq) }

        case let .clientConnect(payload):
            logger.info("Client connected: \(payload.user_ids)")
            if let daveManager = daveSessionManagerLock.read({ $0 }) {
                Task {
                    for userId in payload.user_ids {
                        await daveManager.addUser(userId: userId)
                    }
                }
            }

        case let .clientDisconnect(payload):
            logger.info("Client disconnected: \(payload.user_id)")
            if let daveManager = daveSessionManagerLock.read({ $0 }) {
                Task {
                    await daveManager.removeUser(userId: payload.user_id)
                }
            }

        case let .clientFlags(payload):
            logger.debug("Client flags update: user=\(payload.user_id) flags=\(payload.flags)")

        case let .clientPlatform(payload):
            logger.debug("Client platform update: user=\(payload.user_id) platform=\(payload.platform)")

        case let .davePrepareTransition(payload):
            logger.info("DAVE: Received PREPARE_TRANSITION (ID: \(payload.transitionId), Version: \(payload.protocolVersion), Epoch: \(payload.mlsEpochId))")
            handleDavePrepareTransition(payload)

        case let .daveExecuteTransition(payload):
            logger.info("DAVE: Received EXECUTE_TRANSITION (ID: \(payload.transitionId))")
            handleDaveExecuteTransition(payload)

        case let .davePrepareEpoch(payload):
            logger.info("DAVE: Received PREPARE_EPOCH (Protocol: \(payload.protocolVersion))")
            handleDavePrepareEpoch(payload)

        case let .mlsExternalSenderPackage(payload):
            logger.info("DAVE: Received MLS_EXTERNAL_SENDER_PACKAGE")
            handleMlsExternalSenderPackage(payload)

        case let .mlsProposals(payload):
            logger.info("DAVE: Received MLS_PROPOSALS")
            handleMlsProposals(payload)

        case let .mlsPrepareCommitTransition(payload):
            logger.info("DAVE: Received MLS_PREPARE_COMMIT_TRANSITION (ID: \(payload.transitionId))")
            handleMlsPrepareCommitTransition(payload)

        case let .mlsWelcome(payload):
            logger.info("DAVE: Received MLS_WELCOME (ID: \(payload.transitionId))")
            handleMlsWelcome(payload)

        case .mlsKeyPackage, .mlsCommitWelcome, .mlsInvalidCommitWelcome:
            logger.debug("Received outgoing MLS opcode locally, ignoring")

        case let .close(closeFrame):
            logger.warning("Gateway WebSocket closed: \(closeFrame)")
            handleDisconnect(reason: .close(closeFrame))

        case let .error(error):
            logger.error("Gateway WebSocket error: \(error)")
            handleDisconnect(reason: .error(error))
        }

        onEvent?(event)
    }

    private func handleDavePrepareTransition(_ payload: DavePrepareTransitionPayload) {
        let capturedGen = connectionGeneration.read { $0 }

        let transitionTask = Task { [weak self] in
            guard let self = self else { return }

            let isCurrentGen = self.connectionGeneration.read { $0 == capturedGen }
            guard isCurrentGen else { return }

            do {
                if let daveSessionManager = self.daveSessionManagerLock.read({ $0 }) {
                    await daveSessionManager.prepareTransition(
                        transitionId: UInt16(payload.transitionId),
                        protocolVersion: UInt16(payload.protocolVersion)
                    )
                }
            }
        }

        tasksLock.write { $0.handshake = transitionTask }
    }

    private func handleDaveExecuteTransition(_ payload: DaveExecuteTransitionPayload) {
        let capturedGen = connectionGeneration.read { $0 }

        let executeTask = Task { [weak self] in
            guard let self = self else { return }

            let isCurrentGen = self.connectionGeneration.read { $0 == capturedGen }
            guard isCurrentGen else { return }

            if let daveSessionManager = self.daveSessionManagerLock.read({ $0 }) {
                await daveSessionManager.executeTransition(transitionId: UInt16(payload.transitionId))
                self.logger.info("DAVE: Transition \(payload.transitionId) executed.")
            }
        }

        tasksLock.write { $0.handshake = executeTask }
    }

    private func handleDavePrepareEpoch(_ payload: DavePrepareEpochPayload) {
        Task { [weak self] in
            guard let daveManager = self?.daveSessionManagerLock.read({ $0 }) else { return }
            await daveManager.prepareEpoch(epoch: payload.epochAuthenticator, protocolVersion: UInt16(payload.protocolVersion))
        }
    }

    private func handleMlsExternalSenderPackage(_ payload: MlsExternalSenderPackagePayload) {
        Task { [weak self] in
            guard let daveManager = self?.daveSessionManagerLock.read({ $0 }) else { return }
            await daveManager.mlsExternalSenderPackage(externalSenderPackage: payload.data)
        }
    }

    private func handleMlsProposals(_ payload: MlsProposalsPayload) {
        Task { [weak self] in
            guard let daveManager = self?.daveSessionManagerLock.read({ $0 }) else { return }
            await daveManager.mlsProposals(proposals: payload.data)
        }
    }

    private func handleMlsPrepareCommitTransition(_ payload: MlsPrepareCommitTransitionPayload) {
        Task { [weak self] in
            guard let daveManager = self?.daveSessionManagerLock.read({ $0 }) else { return }
            await daveManager.mlsPrepareCommitTransition(transitionId: payload.transitionId, commit: payload.data)
        }
    }

    private func handleMlsWelcome(_ payload: MlsWelcomePayload) {
        Task { [weak self] in
            guard let daveManager = self?.daveSessionManagerLock.read({ $0 }) else { return }
            await daveManager.mlsWelcome(transitionId: payload.transitionId, welcome: payload.data)
        }
    }

    private func startHeartbeats(intervalMs: Double) {
        stopHeartbeats()

        let hb = HeartbeatManager(
            intervalMs: intervalMs,
            sendHeartbeat: { [weak self] seq in
                Task {
                    let payload = HeartbeatPayload(t: seq, seqAck: nil)
                    try? await self?.connectionLock.read { $0 }?.send(op: .heartbeat, data: payload)
                }
            },
            onTimeout: { [weak self] in
                self?.handleHeartbeatTimeout()
            },
            logger: logger
        )

        heartbeatLock.write { $0 = hb }
        hb.start()
    }

    private func handleHeartbeatTimeout() {
        logger.error("Voice Gateway connection is unresponsive (heartbeat timeout)")
        Task {
            stopHeartbeats()
            let conn = connectionLock.write { old -> GatewayConnection? in
                let temp = old
                old = nil
                return temp
            }
            if let conn {
                try? await conn.close(code: 4009)
            }
            handleDisconnect(reason: .close(GatewayClose(code: 4009, reason: "Heartbeat timeout")))
        }
    }

    private func sendIdentify() async throws {
        guard let session = sessionLock.read({ $0 }),
              let conn = connectionLock.read({ $0 }) else { return }

        let payload = IdentifyPayload(
            serverId: session.serverId,
            userId: session.userId,
            sessionId: session.sessionId,
            token: session.token
        )

        logger.debug("Sending Identify payload")
        try await conn.send(op: .identify, data: payload)
    }

    private func sendResume() async throws {
        guard let session = sessionLock.read({ $0 }),
              let conn = connectionLock.read({ $0 }) else { return }

        let payload = ResumePayload(
            serverId: session.serverId,
            sessionId: session.sessionId,
            token: session.token
        )

        logger.debug("Sending Resume payload")
        try await conn.send(op: .resume, data: payload)
    }

    private enum DisconnectReason {
        case close(GatewayClose)
        case error(Error)
    }

    private func handleDisconnect(reason: DisconnectReason) {
        stopHeartbeats()

        if stateMachine.current == .disconnected {
            return
        }

        var shouldReconnect = true
        var tryResume = false

        switch reason {
        case let .close(closeFrame):
            if let closeCode = closeFrame.closeCode {
                switch closeCode {
                case .normalClosure,
                     .authenticationFailed,
                     .disconnected,
                     .serverNotFound,
                     .unknownProtocol,
                     .unknownEncryptionMode:
                    shouldReconnect = false
                case .sessionNoLongerValid:
                    shouldReconnect = true
                    tryResume = false
                    isResumePending.write { $0 = false }
                default:
                    shouldReconnect = true
                    tryResume = isResumePending.read { $0 }
                }
            } else {
                shouldReconnect = true
                tryResume = isResumePending.read { $0 }
            }
        case .error:
            shouldReconnect = true
            tryResume = isResumePending.read { $0 }
        }

        if shouldReconnect {
            isResumePending.write { $0 = tryResume }
            stateMachine.transition(to: .reconnecting)
            triggerReconnect()
        } else {
            logger.error("Voice Gateway disconnected permanently (non-recoverable error)")
            isResumePending.write { $0 = false }

            let udp = udpConnectionLock.write { old -> UDPConnection? in
                let temp = old
                old = nil
                return temp
            }
            if let udp {
                Task {
                    await udp.close()
                }
            }

            voiceEncryptionLock.write { $0 = nil }
            ssrcLock.write { $0 = nil }

            stateMachine.transition(to: .disconnected)
        }
    }

    private func triggerReconnect() {
        let capturedGen = connectionGeneration.read { $0 }

        let reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            let delay = self.reconnectManager.nextDelay()
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            let isCurrentGen = self.connectionGeneration.read { $0 == capturedGen }
            guard isCurrentGen else {
                self.logger.debug("Reconnect task aborted: connection generation has advanced")
                return
            }

            guard self.stateMachine.current == .reconnecting else { return }

            self.logger.info("Attempting reconnection to Voice Gateway...")
            do {
                try await self.performConnect()
            } catch {
                self.logger.error("Reconnection attempt failed")
            }
        }

        tasksLock.write { $0.reconnect = reconnectTask }
    }

    func sendSpeaking(isSpeaking: Bool, ssrc: UInt32) async throws {
        guard let conn = connectionLock.read({ $0 }), stateMachine.current == .ready else {
            throw VoiceError.webSocketClosed(1006, "Connection not active")
        }

        let bitmask = isSpeaking ? 1 : 0
        let payload = SpeakingPayload(speaking: bitmask, delay: 0, ssrc: ssrc)

        logger.debug("Transmitting speaking payload: \(isSpeaking)")
        try await conn.send(op: .speaking, data: payload)
    }
}

extension VoiceGateway: DaveSessionDelegate {
    public func mlsKeyPackage(keyPackage: Data) async {
        guard !keyPackage.isEmpty else {
            logger.warning("DAVE: Skipping empty MLS key package")
            return
        }
        logger.info("DAVE: Sending MLS_KEY_PACKAGE (\(keyPackage.count) bytes)")
        try? await connectionLock.read { $0 }?.sendBinary(op: .mlsKeyPackage, payload: keyPackage)
    }

    public func readyForTransition(transitionId: UInt16) async {
        logger.info("DAVE: Sending READY_FOR_TRANSITION (ID: \(transitionId))")
        let payload = DaveTransitionReadyPayload(transitionId: Int(transitionId))
        try? await connectionLock.read { $0 }?.send(op: .daveTransitionReady, data: payload)
    }

    public func mlsCommitWelcome(welcome: Data) async {
        logger.info("DAVE: Sending MLS_COMMIT_WELCOME (\(welcome.count) bytes)")
        try? await connectionLock.read { $0 }?.sendBinary(op: .mlsCommitWelcome, payload: welcome)
    }

    public func mlsInvalidCommitWelcome(transitionId: UInt16) async {
        logger.info("DAVE: Sending MLS_INVALID_COMMIT_WELCOME (ID: \(transitionId))")

        var payload = Data(capacity: 2)
        payload.append(UInt8((transitionId >> 8) & 0xFF))
        payload.append(UInt8(transitionId & 0xFF))
        try? await connectionLock.read { $0 }?.sendBinary(op: .mlsInvalidCommitWelcome, payload: payload)
    }
}
