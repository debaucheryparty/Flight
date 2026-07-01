# connection lifecycle 🔌

just like songbird has a robust driver state machine, flight meticulously tracks the state of your voice connection. the internet is messy. websockets drop, udp packets get lost, and discord servers sometimes just kick you out for no reason. 

flight handles this gracefully.

### the state machine

at any given time, your `VoiceClient` is in one of these states:

1. `.disconnected`: the initial state. totally offline.
2. `.connecting`: you called `client.connect()`. flight is currently doing the websocket handshake with discord.
3. `.discovering`: websocket is done, now flight is performing udp hole punching (ip discovery) to figure out how to route the audio out of your local network.
4. `.ready`: connection is rock solid. DAVE e2ee is initialized. you are clear to blast audio.
5. `.reconnecting`: something broke (like a network drop or discord restart). flight is aggressively trying to get you back online without you having to lift a finger.

### handling disconnects and drops

you don't have to write custom logic to reconnect if the connection drops. flight's `VoiceGateway` automatically implements an exponential backoff reconnect loop.

if discord's server crashes and the websocket closes with a `1006` error, flight instantly transitions to `.reconnecting`, buffers your audio, spins up a new websocket, and resumes exactly where it left off.

if you want to track this in your bot (maybe to pause playback temporarily or notify the user), just listen to `onStateChange`:

```swift
client.onStateChange = { state in
    if state == .reconnecting {
        // tell your user to hold tight
        print("discord dropped us. flight is auto-reconnecting right now...")
        
        // maybe pause the player so the song doesn't keep progressing in the void
        player.pause()
    }
    
    if state == .ready {
        print("we're back baby!")
        player.resume()
    }
}
```

### clean shutdowns

when you are done, you should always cleanly disconnect. this sends a polite `GatewayClose` frame to discord and tears down the udp sockets so you don't leak memory.

```swift
await client.disconnect()
```
