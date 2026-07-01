# Usage & Examples

using flight is designed to be dead simple. no boilerplate, no messy state management. just connect and throw audio at it.

### Connecting To A Voice Channel

when discord tells your bot that it joined a voice channel, it sends you a token, an endpoint, and a session id. you just hand those over to flight and it does the rest.

```swift
import Flight

// 1. spin up a voice client
let client = VoiceClient()

// 2. hook up some callbacks so you know what's happening
client.onReady = { ssrc in
    print("connected and ready to beam audio! our ssrc is: \(ssrc)")
}
client.onError = { error in
    print("whoops, something broke: \(error)")
}

// 3. tell it to connect!
try await client.connect(
    serverId: "123456789", 
    userId: "987654321",
    sessionId: "abc123session",
    token: "super_secret_voice_token",
    endpoint: "us-east-1.discord.gg"
)
```

### Playing Audio

flight has a built in `AudioPlayer` that handles all the Opus encoding and 20ms frame timing for you. if you want to stream from youtube or a local file, just use the `FFmpegSource`.

```swift
// hook the player to your client
let player = try AudioPlayer(client: client)

// grab audio from literally anywhere (local file, http stream, youtube search)
let source = try FFmpegSource(query: "ytsearch:rick astley never gonna give you up")

// wrap it in a track
let track = Track(source: source, metadata: TrackMetadata(title: "rickroll"))

// hit play! flight handles the rest in the background.
player.play(track)
```

### Controlling Playback

the `AudioPlayer` gives you full control. pause, resume, volume, you name it.

```swift
// drop the beat
player.pause()

// bring it back
player.resume()

// set the volume (0.0 to 1.0)
player.setVolume(0.5)

// stop playing entirely and clean up
player.stop()
```

### Queueing Multiple Songs

wanna play a whole playlist? use the `QueueManager`.

```swift
let queue = QueueManager()

// queue up a bunch of bangers
queue.enqueue(track1)
queue.enqueue(track2)
queue.enqueue(track3)

// tell the player to run through the queue automatically
player.play(queue: queue)

// skip to the next song if the current one is boring
player.skip()
```

### Disconnecting

when the party is over, just tell the client to pack up and leave cleanly.

```swift
await client.disconnect()
```

and that's literally it! you've got a fully functioning discord music bot. 🎸
