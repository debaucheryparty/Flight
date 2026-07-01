import Foundation

public protocol DaveSessionDelegate: AnyObject, Sendable {
    func mlsKeyPackage(keyPackage: Data) async

    func readyForTransition(transitionId: UInt16) async

    func mlsCommitWelcome(welcome: Data) async

    func mlsInvalidCommitWelcome(transitionId: UInt16) async
}
