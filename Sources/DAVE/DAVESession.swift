import CLibdave
import Foundation

class DaveSession {
    private let sessionHandle: DAVESessionHandle
    init() {
        sessionHandle = daveSessionCreate(nil, nil, { _, _, _ in }, nil)
    }

    deinit {
        daveSessionDestroy(self.sessionHandle)
    }

    func getKeyRatchet(userId: String) -> KeyRatchet {
        KeyRatchet(handle: daveSessionGetKeyRatchet(sessionHandle, userId))
    }

    func reset() {
        daveSessionReset(sessionHandle)
    }

    func setExternalSenderPackage(externalSenderPackage: Data) {
        externalSenderPackage.withUnsafeBytes { externalSenderPackage in
            let externalSenderPackage = externalSenderPackage.bindMemory(to: UInt8.self)
            daveSessionSetExternalSender(
                self.sessionHandle,
                externalSenderPackage.baseAddress!,
                externalSenderPackage.count
            )
        }
    }

    func initialize(version: UInt16, groupId: UInt64, selfUserId: String) {
        daveSessionInit(sessionHandle, version, groupId, selfUserId)
    }

    func getKeyPackage() -> Data {
        var outputLength = 0
        var data: UnsafeMutablePointer<UInt8>?
        daveSessionGetMarshalledKeyPackage(
            sessionHandle,
            &data,
            &outputLength
        )

        guard let data, outputLength > 0 else {
            return Data()
        }
        defer { daveFree(data) }
        return Data(bytes: data, count: outputLength)
    }

    func getProtocolVersion() -> UInt16 {
        daveSessionGetProtocolVersion(sessionHandle)
    }

    func processProposals(proposals: Data, knownUserIds: [String]) -> Data? {
        var welcomeData: UnsafeMutablePointer<UInt8>?
        var welcomeDataLength = 0
        let knownUserIdCount = knownUserIds.count

        let cStrings = knownUserIds.map { strdup($0) }
        var cStringPointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        defer { cStrings.forEach { free($0) } }

        cStringPointers.withUnsafeMutableBufferPointer { knownUserIdsPtr in
            proposals.withUnsafeBytes { proposalsBytes in
                let proposalsPtr = proposalsBytes.bindMemory(to: UInt8.self)
                daveSessionProcessProposals(
                    self.sessionHandle,
                    proposalsPtr.baseAddress!,
                    proposalsBytes.count,
                    knownUserIdsPtr.baseAddress,
                    knownUserIdCount,
                    &welcomeData,
                    &welcomeDataLength
                )
            }
        }

        if let result = welcomeData, welcomeDataLength > 0 {
            return Data(bytes: result, count: welcomeDataLength)
        } else {
            return nil
        }
    }

    func processWelcome(welcome: Data, knownUserIds: [String]) -> Welcome? {
        let knownUserIdCount = knownUserIds.count

        let cStrings = knownUserIds.map { strdup($0) }
        var cStringPointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        defer { cStrings.forEach { free($0) } }

        let result = cStringPointers.withUnsafeMutableBufferPointer { knownUserIdsPtr in
            welcome.withUnsafeBytes { welcomeBytes in
                let welcomePtr = welcomeBytes.bindMemory(to: UInt8.self)
                return daveSessionProcessWelcome(
                    self.sessionHandle,
                    welcomePtr.baseAddress!,
                    welcomeBytes.count,
                    knownUserIdsPtr.baseAddress,
                    knownUserIdCount
                )
            }
        }

        if let result {
            return Welcome(handle: result)
        } else {
            return nil
        }
    }

    func processCommit(commit: Data) -> Commit? {
        let handle = commit.withUnsafeBytes { commit in
            let commit = commit.bindMemory(to: UInt8.self)
            return daveSessionProcessCommit(
                self.sessionHandle,
                commit.baseAddress!,
                commit.count
            )
        }

        if let handle {
            return Commit(handle: handle)
        } else {
            return nil
        }
    }
}
