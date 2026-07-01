import Foundation

public enum FFmpegSourceError: Error {
    case executableNotFound(String)
    case processStartFailed(Error)
    case pipeClosed
}

public final class FFmpegSource: AudioSource, @unchecked Sendable {
    private let ytDlpProcess: Process?
    private let ffmpegProcess: Process
    private let stdoutPipe: Pipe

    private let isTerminated = Protected<Bool>(false)

    public init(query: String) throws {
        stdoutPipe = Pipe()

        let ffmpegProcess = Process()
        guard let ffmpegPath = FFmpegSource.findExecutable(name: "ffmpeg") else {
            throw FFmpegSourceError.executableNotFound("ffmpeg")
        }

        ffmpegProcess.executableURL = ffmpegPath

        ffmpegProcess.arguments = [
            "-i", "pipe:0",
            "-f", "s16le",
            "-ar", "48000",
            "-ac", "2",
            "-loglevel", "quiet",
            "pipe:1",
        ]
        ffmpegProcess.standardOutput = stdoutPipe

        if query.hasPrefix("http") || query.hasPrefix("ytsearch:") || query.hasPrefix("ytsearch1:") {
            let ytDlpProcess = Process()
            guard let ytDlpPath = FFmpegSource.findExecutable(name: "yt-dlp") else {
                throw FFmpegSourceError.executableNotFound("yt-dlp")
            }
            ytDlpProcess.executableURL = ytDlpPath
            let search = query.hasPrefix("http") ? query : (query.hasPrefix("ytsearch") ? query : "ytsearch1:\(query)")
            ytDlpProcess.arguments = ["-f", "bestaudio", "-q", "-o", "-", search]

            let connectingPipe = Pipe()
            ytDlpProcess.standardOutput = connectingPipe
            ffmpegProcess.standardInput = connectingPipe

            self.ytDlpProcess = ytDlpProcess
        } else {
            ytDlpProcess = nil
            ffmpegProcess.arguments = [
                "-i", query,
                "-f", "s16le",
                "-ar", "48000",
                "-ac", "2",
                "-loglevel", "quiet",
                "pipe:1",
            ]
        }

        self.ffmpegProcess = ffmpegProcess

        do {
            try ytDlpProcess?.run()
            try self.ffmpegProcess.run()
        } catch {
            throw FFmpegSourceError.processStartFailed(error)
        }
    }

    deinit {
        stop()
    }

    public func stop() {
        let wasTerminated = isTerminated.write { old -> Bool in
            let temp = old
            old = true
            return temp
        }

        guard !wasTerminated else { return }

        ytDlpProcess?.terminate()
        ffmpegProcess.terminate()

        try? stdoutPipe.fileHandleForReading.close()
    }

    public func readFrame() async -> [Int16]? {
        let frameSize = 3840

        return await Task.detached { [weak self] () -> [Int16]? in
            guard let self else { return nil }

            let isTerm = isTerminated.read { $0 }
            if isTerm { return nil }

            do {
                guard let data = try stdoutPipe.fileHandleForReading.read(upToCount: frameSize) else {
                    stop()
                    return nil
                }

                if data.isEmpty {
                    stop()
                    return nil
                }

                var pcm = [Int16](repeating: 0, count: data.count / 2)
                _ = pcm.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                return pcm
            } catch {
                stop()
                return nil
            }
        }.value
    }

    private static func findExecutable(name: String) -> URL? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            let data: Data = if #available(macOS 10.15, *) {
                (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            } else {
                pipe.fileHandleForReading.readDataToEndOfFile()
            }
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
