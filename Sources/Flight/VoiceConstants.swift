import Foundation

public enum VoiceConstants {
    public static let sampleRate = 48000
    public static let channels = 2

    public static let frameDurationMs = 20

    public static let samplesPerFrame = 960

    public static let rtpPayloadTypeOpus: UInt8 = 120

    public static let discoveryPacketSize = 74

    public static let defaultBaseReconnectDelay = 1.0
    public static let defaultMaxReconnectDelay = 60.0
    public static let defaultReconnectJitter = 0.5
}
