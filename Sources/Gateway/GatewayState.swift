import Foundation

enum GatewayState: Equatable {
    case disconnected
    case connecting
    case identifying
    case discovering
    case negotiating
    case ready
    case reconnecting
}
