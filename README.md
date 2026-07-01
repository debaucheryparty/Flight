# Flight

> Standalone, pure Swift Discord voice library

<p align="center">
    <img src="resources/flight.png" alt="Flight Logo" width="250"> 
</p>

> The smoothest way to fly audio into Discord

## Features

- Voice Gateway
  - [x] Seamless Connect / Disconnect
  - [x] Auto-Reconnecting & Resumes
  - [x] Invisible DAVE (End-to-End Encryption) Support
  - [x] Granular State Tracking
- Playback
  - [x] Play, Pause, Resume, Stop
  - [x] Real-time Volume Control
  - [x] Dynamic `AudioMixer` for playing multiple tracks simultaneously
  - [x] Track Queueing (`QueueManager`)
- Audio Pipeline
  - [x] Opus Encoding / Decoding
  - [x] Smart Jitter Buffering (Sequence Sorting, PLC triggering)
  - [x] Strict Continuous Clock Frame Scheduling (20ms)
- Events
  - [x] `trackStarted` & `trackFinished`
  - [x] `onUserConnect` & `onUserDisconnect`
  - [x] Receive Voice Audio (`onAudioReceived`)

## Sources

- [x] FFmpeg (`FFmpegSource`)
  - Supports local files, HTTP streams, and everything FFmpeg can parse
- [x] Youtube / SoundCloud (`FFmpegSource` via `yt-dlp`)
  - Supported automatically via `ytsearch:` and `scsearch:` queries
- [x] Raw PCM (`AudioMixer` / Custom Sources)
  - Full support for writing your own custom `AudioSource` generator
- [x] DCA / Pre-encoded Opus (`OpusSource`)
  - Bypasses CPU-heavy encoding entirely for pre-processed `.dca` files

## Documentation

- Comprehensive documentation is available in the [`Book`](Book/) directory. Check out the [Installation Guide](Book/INSTALLATION.md) to get started!

## Installation

- Keep in mind that **Flight is heavily in active development**. For issues, please open an issue in the [Issues Tab](https://github.com/debaucheryparty/Flight/issues).
- Flight is distributed via the Swift Package Manager. Just drop this in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/debaucheryparty/Flight.git", branch: "main")
]
```

- *Note: You must enable C++ Interoperability (`.interoperabilityMode(.Cxx)`) on your target to use Flight's encryption suite smoothly.*

## Contributing
- The dev environment used in this project is:
  - macOS / Linux
  - Swift toolchain: `Swift 6.0+`
  - System Dependencies: `ffmpeg`, `yt-dlp`
- This should enable you to fork, compile, and test the project before opening a PR.

If you need help or ask for help, feel free to open a Discussion on GitHub or reach out to the maintainers!
