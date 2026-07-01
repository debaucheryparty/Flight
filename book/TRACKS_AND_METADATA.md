# tracks and metadata 🎵

like songbird, flight doesn't just treat audio as raw bytes. everything you play is wrapped in a `Track`. this lets you attach metadata, track state, and manage your queues intelligently.

### building a track

when you create a track, you pass it an `AudioSource` (like ffmpeg) and some `TrackMetadata`.

```swift
let source = try FFmpegSource(query: "ytsearch:rick roll")

// metadata lets you store info about the song so you can read it back later!
let meta = TrackMetadata(
    title: "never gonna give you up",
    url: "https://youtube.com/watch?v=dQw4w9WgXcQ",
    durationMs: 212000 
)

let track = Track(source: source, metadata: meta)
```

### checking what's currently playing

because we attached metadata, your discord commands (like `!nowplaying`) can instantly tell the user what is currently bumping.

```swift
if let current = player.currentTrack {
    print("now playing: \(current.metadata.title)")
    print("link: \(current.metadata.url ?? "unknown")")
} else {
    print("crickets... nothing is playing right now.")
}
```

### global player events

flight gives you a global async stream for all player events. this is how you build a robust music bot that automatically sends "now playing" messages to the discord text channel.

```swift
Task {
    for await event in player.events {
        switch event {
        case .trackStarted(let track):
            // song just started! send a message to discord
            await sendDiscordMessage("▶️ now playing: \(track.metadata.title)")
            
        case .trackFinished(let track, let reason):
            // song ended. why did it end?
            switch reason {
            case .finished: print("song played all the way through naturally.")
            case .skipped:  print("somebody skipped this banger.")
            case .stopped:  print("playback was force stopped.")
            }
            
        case .stateChanged(let from, let to):
            print("player state changed from \(from) to \(to)")
            
        case .error(let error):
            print("audio player choked on something: \(error)")
        }
    }
}
```

### queue management

the `QueueManager` uses tracks to build a continuous playlist. you can query it at any time to build a `!queue` command.

```swift
let q = QueueManager()
q.enqueue(track1)
q.enqueue(track2)

print("there are \(q.tracks.count) songs in the queue!")
for (index, track) in q.tracks.enumerated() {
    print("\(index + 1). \(track.metadata.title)")
}
```
