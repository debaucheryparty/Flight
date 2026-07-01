import Foundation

final class Protected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read<T>(_ block: (Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block(value)
    }

    func write<T>(_ block: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block(&value)
    }

    func compareExchange(expected: Value, desired: Value) -> Bool where Value: Equatable {
        lock.lock()
        defer { lock.unlock() }
        if value == expected {
            value = desired
            return true
        }
        return false
    }
}
