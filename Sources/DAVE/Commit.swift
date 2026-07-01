import CLibdave

class Commit {
    private let handle: DAVECommitResultHandle

    init(handle: DAVECommitResultHandle) {
        self.handle = handle
    }

    deinit {
        daveCommitResultDestroy(self.handle)
    }

    var isFailed: Bool {
        return daveCommitResultIsFailed(handle)
    }

    var isIgnored: Bool {
        return daveCommitResultIsIgnored(handle)
    }
}
