import Foundation

final class AsyncState<State: Equatable & Sendable>: @unchecked Sendable {
    private struct Waiter {
        let predicate: @Sendable (State) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock: Protected<(state: State, waiters: [Waiter])>

    init(_ initialState: State) {
        lock = Protected((initialState, []))
    }

    var current: State {
        lock.read { $0.state }
    }

    func transition(to newState: State) {
        var toResume: [CheckedContinuation<Void, Never>] = []

        lock.write { data in
            data.state = newState
            var keptWaiters: [Waiter] = []
            for waiter in data.waiters {
                if waiter.predicate(newState) {
                    toResume.append(waiter.continuation)
                } else {
                    keptWaiters.append(waiter)
                }
            }
            data.waiters = keptWaiters
        }

        for continuation in toResume {
            continuation.resume()
        }
    }

    func waitFor(_ predicate: @escaping @Sendable (State) -> Bool) async {
        let alreadySatisfied = lock.read { predicate($0.state) }
        if alreadySatisfied {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.write { data in
                if predicate(data.state) {
                    continuation.resume()
                } else {
                    data.waiters.append(Waiter(predicate: predicate, continuation: continuation))
                }
            }
        }
    }

    func waitFor(_ targetState: State) async {
        await waitFor { $0 == targetState }
    }
}
