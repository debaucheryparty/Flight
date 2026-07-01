# events and listening 📡

a voice bot isn't just about throwing audio into the void. sometimes you want to know who is in the channel, when they leave, or even listen to what they are saying. 

flight exposes a clean event system right on the `VoiceClient`.

### the callback hooks

```swift
import Flight

let client = VoiceClient()

// triggered when a user joins the voice channel
client.onUserConnect = { userIds in
    for id in userIds {
        print("user \(id) hopped in the channel!")
    }
}

// triggered when a user drops out
client.onUserDisconnect = { userId in
    print("user \(userId) left the channel. bye!")
}

// triggered when the connection state shifts around
client.onStateChange = { state in
    switch state {
    case .connecting: print("handshaking...")
    case .ready: print("we are online and ready to rock.")
    case .reconnecting: print("uh oh, internet blip. reconnecting...")
    case .disconnected: print("we are out.")
    default: break
    }
}
```

### listening to incoming audio (receiving)

flight isn't just a sender. it has a fully featured receiver with a jitter buffer and opus decoders built in. it automatically decrypts DAVE E2EE audio streams and gives you clean PCM data per user.

```swift
client.onAudioReceived = { userId, pcmFrame in
    // userId: the discord user who is currently speaking
    // pcmFrame: an array of Int16 containing exactly 20ms of their voice (48kHz stereo)

    print("user \(userId) just sent \(pcmFrame.count) samples of audio!")
    
    // you could pipe this into a speech-to-text engine
    // or record it to a file
    // or apply voice filters and stream it back!
}
```

*note: receiving audio is computationally heavy because it has to run a separate jitter buffer and opus decoder for every single user currently speaking in the channel. flight handles it asynchronously in the background so it won't block your main thread.*
