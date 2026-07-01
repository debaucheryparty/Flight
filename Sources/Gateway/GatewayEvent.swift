import Foundation

enum GatewayEvent {
    case hello(HelloPayload)
    case ready(ReadyPayload)
    case resumed
    case sessionDescription(SessionDescriptionPayload)
    case speaking(SpeakingPayload)
    case heartbeatAck(Int)
    case close(GatewayClose)
    case error(Error)

    case clientConnect(ClientConnectPayload)
    case clientDisconnect(ClientDisconnectPayload)
    case clientFlags(ClientFlagsPayload)
    case clientPlatform(ClientPlatformPayload)

    case davePrepareTransition(DavePrepareTransitionPayload)
    case daveExecuteTransition(DaveExecuteTransitionPayload)
    case davePrepareEpoch(DavePrepareEpochPayload)
    case mlsExternalSenderPackage(MlsExternalSenderPackagePayload)
    case mlsKeyPackage(MlsKeyPackagePayload)
    case mlsProposals(MlsProposalsPayload)
    case mlsCommitWelcome(MlsCommitWelcomePayload)
    case mlsPrepareCommitTransition(MlsPrepareCommitTransitionPayload)
    case mlsWelcome(MlsWelcomePayload)
    case mlsInvalidCommitWelcome(MlsInvalidCommitWelcomePayload)
}
