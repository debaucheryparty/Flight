# Error Handling

things go wrong. maybe ffmpeg isn't installed. maybe your bot token expired. flight tries to throw highly descriptive errors so you never have to scratch your head.

### The Dreaded `Onerror` Hook

if something unrecoverable happens inside the `VoiceClient` loop (like the DAVE e2ee handshake completely failing, or discord refusing to authorize your token), flight emits an error through the `onError` hook.

```swift
client.onError = { error in
    if let voiceError = error as? VoiceError {
        switch voiceError {
        case .handshakeFailed(let reason):
            print("discord rejected us! reason: \(reason)")
        case .webSocketClosed(let code, let msg):
            print("socket died: \(code) - \(msg)")
        default:
            print("some wild error appeared: \(voiceError)")
        }
    }
}
```

### Catching Initialization Errors

most errors happen right when you try to start something. flight throws synchronously here so you can catch them immediately.

```swift
do {
    let source = try FFmpegSource(query: "ytsearch:cats")
} catch FFmpegSourceError.executableNotFound(let bin) {
    print("bro, you need to install \(bin)! try running `brew install ffmpeg yt-dlp`")
} catch {
    print("couldn't start ffmpeg: \(error)")
}
```

```swift
do {
    let encoder = try OpusEncoder()
} catch VoiceError.opusError(let code, let msg) {
    print("opus c library choked with code \(code): \(msg)")
}
```

### Debugging

flight uses `swift-log`. if you are trying to figure out why your connection is stuck or why packets are dropping, turn your log level up to `.debug` or `.trace`.

```swift
import Logging

// set global log level
var logger = Logger(label: "Flight")
logger.logLevel = .debug
```

flight will spit out everything: from raw RTP packet assembly traces, to MLS key ratchet states, to UDP socket drops. it's incredibly verbose when you need it to be.
