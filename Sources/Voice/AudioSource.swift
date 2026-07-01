import Foundation

public protocol AudioSource: Sendable {
    func readFrame() async -> [Int16]?
}
