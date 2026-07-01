import Foundation
import NIOCore

public struct FlightConfiguration: Sendable {
    public var baseReconnectDelay: Double
    public var maxReconnectDelay: Double
    public var reconnectJitter: Double
    public var gatewayVersion: Int
    public var connectionTimeout: TimeAmount

    public init(
        baseReconnectDelay: Double = VoiceConstants.defaultBaseReconnectDelay,
        maxReconnectDelay: Double = VoiceConstants.defaultMaxReconnectDelay,
        reconnectJitter: Double = VoiceConstants.defaultReconnectJitter,
        gatewayVersion: Int = 8,
        connectionTimeout: TimeAmount = .seconds(10),
    ) {
        self.baseReconnectDelay = baseReconnectDelay
        self.maxReconnectDelay = maxReconnectDelay
        self.reconnectJitter = reconnectJitter
        self.gatewayVersion = gatewayVersion
        self.connectionTimeout = connectionTimeout
    }
}
