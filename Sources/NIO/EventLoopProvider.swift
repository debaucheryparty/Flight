import NIOCore
import NIOPosix

enum EventLoopProvider {
    static let sharedGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
}
