import NIOCore
import NIOSSL

struct NIOConfiguration {
    var tlsConfiguration: TLSConfiguration

    init(tlsConfiguration: TLSConfiguration = .makeClientConfiguration()) {
        self.tlsConfiguration = tlsConfiguration
    }
}
