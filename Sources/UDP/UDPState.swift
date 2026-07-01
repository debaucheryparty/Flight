import Foundation

enum UDPState: Equatable {
    case idle
    case connecting
    case discovering
    case ready
}
