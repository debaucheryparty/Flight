# audio sources 🎶

flight uses an abstraction called `AudioSource`. basically anything that can spit out a 20ms frame of audio can be played. we have a bunch built-in for you so you dont have to reinvent the wheel.

### 1. ffmpeg source (the heavy lifter)

this is what you will use 99% of the time. it pipelines `yt-dlp` straight into `ffmpeg` so you can play literally anything. local files, youtube links, soundcloud, raw urls, whatever.

```swift
// throw a youtube link at it
let source1 = try FFmpegSource(query: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

// or just search directly
let source2 = try FFmpegSource(query: "ytsearch:lofi hip hop radio")

// or a local file
let source3 = try FFmpegSource(query: "/path/to/my/epic_beat.mp3")

// stick it in a track and play it
let track = Track(source: source1, metadata: TrackMetadata(title: "never gonna give you up"))
player.play(track)
```
*pro tip: the ffmpeg source handles all the cleanup automatically. no zombie processes left behind.*

### 2. audio mixer (play multiple things at once)

want background music while playing sound effects over it? use the mixer. it reads from multiple sources concurrently and mixes their pcm data perfectly so it doesn't clip or blow out your ears.

```swift
let mixer = AudioMixer()

let bgm = try FFmpegSource(query: "ytsearch:elevator music")
let sfx = try FFmpegSource(query: "airhorn.mp3")

// add them to the mixer
mixer.addSource(bgm)
let sfxId = mixer.addSource(sfx)

// the mixer is an AudioSource itself, so just pass it to the player!
player.play(Track(source: .pcm(mixer), metadata: TrackMetadata(title: "chaos")))

// later if you want to stop just the airhorn:
mixer.removeSource(id: sfxId)
```

### 3. direct opus source (for pre-encoded stuff)

if you already have raw `.dca` files (discord audio format) or pre-encoded opus packets, you skip the cpu-heavy encoding step completely.

```swift
// flight parses dca files instantly
let parsedOpus = try DCAParser.parse(fileURL: dcaUrl)
let opusSource = OpusSource(packets: parsedOpus)

player.play(Track(source: .opus(opusSource), metadata: TrackMetadata(title: "fast boy")))
```

### 4. writing your own source

if you want to generate sine waves or pull audio from a weird api, just conform to `AudioSource`.

```swift
class MyWeirdSource: AudioSource {
    func readFrame() async -> [Int16]? {
        // return exactly 1920 samples (960 per channel for stereo at 48kHz)
        // return nil when the stream is done
        return someCrazyAudioData
    }
}
```
