import Foundation

enum GatewayVersion {
    static let `default` = 8

    static func queryParameter(for version: Int = GatewayVersion.default) -> String {
        return "v=\(version)"
    }
}
