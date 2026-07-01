import Foundation

enum GatewayOpcode: Int, Codable {
    case identify = 0
    case selectProtocol = 1
    case ready = 2
    case heartbeat = 3
    case sessionDescription = 4
    case speaking = 5
    case heartbeatAck = 6
    case resume = 7
    case hello = 8
    case resumed = 9

    case clientConnect = 11
    case clientDisconnect = 13

    case clientFlags = 18
    case clientPlatform = 20

    case davePrepareTransition = 21
    case daveExecuteTransition = 22
    case daveTransitionReady = 23
    case davePrepareEpoch = 24
    case mlsExternalSenderPackage = 25
    case mlsKeyPackage = 26
    case mlsProposals = 27
    case mlsCommitWelcome = 28
    case mlsPrepareCommitTransition = 29
    case mlsWelcome = 30
    case mlsInvalidCommitWelcome = 31
}
