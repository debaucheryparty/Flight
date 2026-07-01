@_exported import CLibdave
import Foundation
import Logging

public actor DaveSessionManager {
    private static let INIT_TRANSITION_ID: UInt16 = 0
    private static let DISABLED_PROTOCOL_VERSION = 0
    private static let MLS_NEW_GROUP_EXPECTED_EPOCH = "1"

    private static let setupLogging: Void = {
        daveSetLogSinkCallback(logSyncCallback)
    }()

    private let selfUserId: String
    private let groupId: UInt64

    private let session: DaveSession
    private let encryptor: Encryptor
    private var decryptors: [String: Decryptor] = [:]

    private var lastPreparedTransitionVersion: UInt16 = 0
    private var preparedTransitions: [UInt16: UInt16] = [:]

    private weak let delegate: (any DaveSessionDelegate)?

    public init(
        selfUserId: String,
        groupId: UInt64,
        delegate: DaveSessionDelegate,
    ) {
        self.selfUserId = selfUserId
        self.groupId = groupId
        self.delegate = delegate

        _ = Self.setupLogging

        session = DaveSession()
        encryptor = Encryptor()
        encryptor.setPassthroughMode(enabled: true)
    }

    public nonisolated static func maxSupportedProtocolVersion() -> UInt16 {
        daveMaxSupportedProtocolVersion()
    }

    private var assignedSsrcs: Set<UInt32> = []

    public func addUser(userId: String) {
        decryptors[userId] = Decryptor()
        setupKeyRatchetForUser(userId: userId, protocolVersion: lastPreparedTransitionVersion)
    }

    public func removeUser(userId: String) {
        decryptors.removeValue(forKey: userId)
    }

    public func encrypt(
        ssrc: UInt32,
        data: Data,
        mediaType: MediaType = .audio,
    ) throws(EncryptError) -> Data {
        // register the ssrc dynamically with the right codec before encrypting first packet
        if !assignedSsrcs.contains(ssrc) {
            let codec = (mediaType == .audio) ? DAVECodec(rawValue: 1)! : DAVECodec(rawValue: 4)!
            encryptor.assignSsrcToCodec(ssrc: ssrc, codec: codec)
            assignedSsrcs.insert(ssrc)
        }
        return try encryptor.encrypt(ssrc: ssrc, data: data, mediaType: mediaType)
    }

    public func decrypt(
        userId: String,
        data: Data,
        mediaType: MediaType = .audio,
    ) throws(DecryptError) -> Data? {
        guard let decryptor = decryptors[userId] else {
            return nil
        }

        return try decryptor.decrypt(data: data, mediaType: mediaType)
    }

    public func selectProtocol(protocolVersion: UInt16) async {
        if protocolVersion > Self.DISABLED_PROTOCOL_VERSION {
            await prepareEpoch(
                epoch: Self.MLS_NEW_GROUP_EXPECTED_EPOCH,
                protocolVersion: protocolVersion,
            )
        } else {
            await prepareTransition(
                transitionId: Self.INIT_TRANSITION_ID,
                protocolVersion: protocolVersion,
            )
            executeTransition(transitionId: Self.INIT_TRANSITION_ID)
        }
    }

    public func prepareTransition(transitionId: UInt16, protocolVersion: UInt16) async {
        for userId in decryptors.keys {
            setupKeyRatchetForUser(userId: userId, protocolVersion: protocolVersion)
        }

        if transitionId == Self.INIT_TRANSITION_ID {
            setupKeyRatchetForEncryptor(protocolVersion: protocolVersion)
        } else {
            preparedTransitions[transitionId] = protocolVersion
        }

        lastPreparedTransitionVersion = transitionId

        if transitionId != Self.INIT_TRANSITION_ID {
            await delegate?.readyForTransition(transitionId: transitionId)
        }
    }

    public func executeTransition(transitionId: UInt16) {
        guard let protocolVersion = preparedTransitions.removeValue(forKey: transitionId) else {
            return
        }

        if protocolVersion == Self.DISABLED_PROTOCOL_VERSION {
            session.reset()
        }

        setupKeyRatchetForEncryptor(protocolVersion: protocolVersion)
    }

    public func prepareEpoch(epoch: String, protocolVersion: UInt16) async {
        guard epoch == Self.MLS_NEW_GROUP_EXPECTED_EPOCH else {
            return
        }

        session.initialize(version: protocolVersion, groupId: groupId, selfUserId: selfUserId)

        await delegate?.mlsKeyPackage(keyPackage: session.getKeyPackage())
    }

    public func mlsExternalSenderPackage(externalSenderPackage: Data) {
        session.setExternalSenderPackage(externalSenderPackage: externalSenderPackage)
    }

    public func mlsProposals(proposals: Data) async {
        let welcome = session.processProposals(proposals: proposals, knownUserIds: knownUserIds)
        if let welcome {
            await delegate?.mlsCommitWelcome(welcome: welcome)
        }
    }

    public func mlsPrepareCommitTransition(transitionId: UInt16, commit: Data) async {
        let commit = session.processCommit(commit: commit)

        guard let commit, !commit.isFailed else {
            await delegate?.mlsInvalidCommitWelcome(transitionId: transitionId)
            await selectProtocol(protocolVersion: session.getProtocolVersion())
            return
        }

        if commit.isIgnored {
            return
        }

        await prepareTransition(transitionId: transitionId, protocolVersion: session.getProtocolVersion())
    }

    public func mlsWelcome(transitionId: UInt16, welcome: Data) async {
        let welcome = session.processWelcome(
            welcome: welcome,
            knownUserIds: knownUserIds,
        )
        guard welcome != nil else {
            await delegate?.mlsInvalidCommitWelcome(transitionId: transitionId)
            await delegate?.mlsKeyPackage(keyPackage: session.getKeyPackage())
            return
        }

        await prepareTransition(
            transitionId: transitionId,
            protocolVersion: session.getProtocolVersion(),
        )
    }

    private var knownUserIds: [String] {
        Array(decryptors.keys) + [selfUserId]
    }

    private func setupKeyRatchetForEncryptor(protocolVersion: UInt16) {
        if protocolVersion == Self.DISABLED_PROTOCOL_VERSION {
            encryptor.setPassthroughMode(enabled: true)
            return
        }

        encryptor.setPassthroughMode(enabled: false)
        encryptor.setKeyRatchet(keyRatchet: session.getKeyRatchet(userId: selfUserId))
    }

    private func setupKeyRatchetForUser(userId: String, protocolVersion: UInt16) {
        guard let decryptor = decryptors[userId] else {
            return
        }

        if protocolVersion == Self.DISABLED_PROTOCOL_VERSION {
            decryptor.transitionToPassthroughMode(enabled: true)
            return
        }

        decryptor.transitionToPassthroughMode(enabled: false)
        decryptor.transitionToKeyRatchet(keyRatchet: session.getKeyRatchet(userId: userId))
    }
}
