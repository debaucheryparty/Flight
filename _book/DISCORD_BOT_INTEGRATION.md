# Discord Bot Integration

flight doesn't care how you get your discord gateway events. it is completely agnostic. as long as you can hand it the `token`, `endpoint`, and `session_id`, it will connect. 

but to give you a real world example, here's how you hook it up using the super popular `DiscordBM` library.

### The Basic Flow

when a user types `!play`, your bot needs to do two things:
1. tell discord "hey, put me in this voice channel".
2. listen for discord to reply with two events: `VOICE_STATE_UPDATE` (gives the session_id) and `VOICE_SERVER_UPDATE` (gives the token and endpoint).

once you have those three pieces of the puzzle, you pass them to flight.

```swift
// inside your discordbm bot handler...

// 1. tell discord to join the voice channel
await bot.updateVoiceState(
    payload: .init(
        guildId: message.guild_id,
        channelId: userVoiceChannelId,
        selfMute: false,
        selfDeaf: false
    )
)

// 2. when you get a VOICE_STATE_UPDATE event for your bot
func handleVoiceStateUpdate(_ voiceState: VoiceState) {
    if voiceState.user_id == myBotId {
        // save this session id! you need it to connect.
        myTempSessionId = voiceState.session_id
    }
}

// 3. when you get a VOICE_SERVER_UPDATE event
func handleVoiceServerUpdate(_ server: Gateway.VoiceServerUpdate) {
    // grab the token and endpoint
    let token = server.token
    let endpoint = server.endpoint
    
    // BOOM. we have all 3 pieces. now hand it to flight.
    Task {
        try await client.connect(
            serverId: server.guild_id.rawValue,
            userId: myBotId.rawValue,
            sessionId: myTempSessionId,
            token: token,
            endpoint: endpoint
        )
        
        // now you're connected. start the music!
        player.play(someTrack)
    }
}
```

### Switching Channels Seamlessly

if the bot is moved to a different voice channel or discord changes the voice server region, discord sends you another `VOICE_SERVER_UPDATE`.

flight handles seamless transitions (meaning the music won't drop) if you just pass the new info to `updateServer`:

```swift
func handleVoiceServerUpdate(_ server: Gateway.VoiceServerUpdate) {
    // if already connected...
    if client.isReady {
        Task {
            // this swaps out the udp connection in the background without dropping frames
            try await client.updateServer(token: server.token, endpoint: server.endpoint)
        }
    }
}
```

that's it. no messy states. just give flight the credentials and it manages the entire voice lifecycle for you.
