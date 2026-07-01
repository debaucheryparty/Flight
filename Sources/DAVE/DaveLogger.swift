import CLibdave

func logSyncCallback(
    severity: DAVELoggingSeverity,
    file: UnsafePointer<CChar>?,
    line: Int32,
    message: UnsafePointer<CChar>?
) {
    guard let message, let file else { return }
    let logMessage = String(cString: message)
    let fileName = String(cString: file)

    if severity == .LOGGING_SEVERITY_VERBOSE { return }
    print("[DAVE] [\(fileName):\(line)] \(logMessage)")
}
