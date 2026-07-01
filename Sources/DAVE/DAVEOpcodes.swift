import Foundation

enum DAVEOpcode: Int, Codable {
    case prepareTransition = 21

    case executeTransition = 22

    case transitionReady = 23
}

struct DavePrepareTransitionPayload: Codable {
    let transitionId: Int
    let protocolVersion: Int
    let mlsEpochId: UInt64

    enum CodingKeys: String, CodingKey {
        case transitionId = "transition_id"
        case protocolVersion = "protocol_version"
        case mlsEpochId = "mls_epoch_id"
    }
}

struct DaveExecuteTransitionPayload: Codable {
    let transitionId: Int

    enum CodingKeys: String, CodingKey {
        case transitionId = "transition_id"
    }
}

struct DaveTransitionReadyPayload: Codable {
    let transitionId: Int

    enum CodingKeys: String, CodingKey {
        case transitionId = "transition_id"
    }
}

struct DavePrepareEpochPayload: Codable {
    let epochAuthenticator: String
    let protocolVersion: Int

    enum CodingKeys: String, CodingKey {
        case epochAuthenticator = "epoch_authenticator"
        case protocolVersion = "protocol_version"
    }
}

struct MlsExternalSenderPackagePayload {
    let data: Data
}

struct MlsKeyPackagePayload {
    let data: Data
}

struct MlsProposalsPayload {
    let data: Data
}

struct MlsCommitWelcomePayload {
    let data: Data
}

struct MlsPrepareCommitTransitionPayload {
    let transitionId: UInt16
    let data: Data
}

struct MlsWelcomePayload {
    let transitionId: UInt16
    let data: Data
}

struct MlsInvalidCommitWelcomePayload {
    let transitionId: UInt16
}
