# advanced stuff 🧠

you probably don't need to read this unless you're a giant nerd trying to dig into the internals. but if you are, here's how the magic works.

### DAVE (end-to-end encryption)

discord recently rolled out DAVE, which is their custom implementation of MLS (messaging layer security) for voice channels. it means audio is fully end-to-end encrypted and discord's servers can't intercept the actual voice data.

in other libraries, this is a nightmare to set up. in flight, **it is completely invisible**.

1. flight negotiates the mls keys via the websocket automatically.
2. it manages key ratcheting for every single user in the channel transparently.
3. it encrypts your outgoing audio using your private key right before shipping it over udp.
4. it decrypts incoming audio from other users seamlessly.

if you just want to know how to turn it on: you don't. it's just on by default if the discord channel supports it.

### the jitter buffer

udp packets arrive out of order, or sometimes they just get lost in the void of the internet. if you just blindly played everything that arrived, the audio would sound like a robot choking.

flight has a built-in `JitterBuffer` for incoming audio. 
- it delays playback slightly (default 40ms) to build up a buffer.
- it sorts incoming packets by their sequence number so they play in perfect chronological order.
- if a packet straight up disappears, the jitter buffer sends an empty payload to the Opus Decoder. the decoder then uses PLC (packet loss concealment) to synthetically guess what the missing audio should have sounded like. it's wild.

### strict timing with `FrameScheduler`

discord expects exactly one packet of audio every 20 milliseconds. if you send them too fast, they buffer and drop them. if you send them too slow, the audio stutters.

flight's `AudioPlayer` uses a `ContinuousClock` based `FrameScheduler` running in a detached swift concurrency task. it loops, awaits the exact nanosecond offset of the next frame, reads from your `AudioSource`, encodes it, and pushes it over the network. 

this guarantees that even if your cpu spikes or your event loop gets blocked by some heavy json parsing, your music stream stays buttery smooth.
