import AsyncHTTPClient
import DiscordBM
import Flight
import Foundation
import NIO

// ensure the required discord bot token is provided via environment variables
guard let token = ProcessInfo.processInfo.environment["DISCORD_TOKEN"] else {
    fatalError("Missing DISCORD_TOKEN environment variable. Please run the bot using: DISCORD_TOKEN=\"your_token\" swift run")
}

// set up the event loop and http client for discordbm
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))

/// initialize the discord bot gateway manager
let bot = await BotGatewayManager(
    eventLoopGroup: eventLoopGroup,
    httpClient: httpClient,
    token: token,
    presence: .init(
        activities: [.init(name: "Type !sounds for Soundboard", type: .listening)],
        status: .online,
        afk: false,
    ),
    intents: [.guilds, .guildMessages, .messageContent, .guildVoiceStates],
)

// global state variables
var myBotId = ""
var userVoiceChannels: [String: String] = [:]

/// this structure groups the required flight components for each server (guild)
/// note we don't use a queuemanager here because a soundboard should interrupt immediately
struct FlightInstance {
    let client: VoiceClient
    let player: AudioPlayer
}

var flightInstances: [String: FlightInstance] = [:]
var tempSessionIds: [String: String] = [:]

/// dictionary of sound effects (mapped to short youtube urls for demonstration)
/// in a production soundboard these should map to local file paths (eg "sounds/hornmp3") for instant zero-latency loading
let soundboard: [String: String] = [
    "!horn": "https://www.youtube.com/watch?v=Wz_DNrKVrQ8",
    "!bruh": "https://www.youtube.com/watch?v=2ZIpFytCSVc",
    "!wow": "https://www.youtube.com/watch?v=FzjqHqE485Q",
    "!sad": "https://www.youtube.com/watch?v=CQeezCdF4cg",
]

// start the bot connection
Task {
    await bot.connect()
}

// the main event loop that processes all incoming discord events
for await event in await bot.events {
    switch event.data {
    case let .ready(ready):
        myBotId = ready.user.id.rawValue
        print("Soundboard Bot connected successfully as \(ready.user.username).")

    case let .voiceStateUpdate(state):
        // track the voice channel of users so the bot knows where to join
        if let channelId = state.channel_id {
            userVoiceChannels[state.user_id.rawValue] = channelId.rawValue
        } else {
            userVoiceChannels.removeValue(forKey: state.user_id.rawValue)
        }

        // save the bot's session id when it joins a voice channel
        if state.user_id.rawValue == myBotId {
            let guildId = state.guild_id.rawValue
            tempSessionIds[guildId] = state.session_id
        }

    case let .voiceServerUpdate(server):
        let guildId = server.guild_id.rawValue
        guard let endpoint = server.endpoint else { continue }
        let voiceToken = server.token
        guard let sessionId = tempSessionIds[guildId] else { continue }

        // if the client is already connected update the server endpoint
        // otherwise initialize a new flight client and connect
        if let instance = flightInstances[guildId], instance.client.isReady {
            Task {
                try? await instance.client.updateServer(token: voiceToken, endpoint: endpoint)
            }
        } else {
            do {
                let client = VoiceClient()
                let player = try AudioPlayer(client: client)

                flightInstances[guildId] = FlightInstance(client: client, player: player)

                // establish the voice connection to discord using flight
                Task {
                    do {
                        try await client.connect(
                            serverId: guildId,
                            userId: myBotId,
                            sessionId: sessionId,
                            token: voiceToken,
                            endpoint: endpoint,
                        )
                        print("Flight connected successfully to server: \(guildId)")
                    } catch {
                        print("Failed to connect Flight: \(error)")
                    }
                }
            } catch {
                print("Failed to initialize AudioPlayer: \(error)")
            }
        }

    case let .messageCreate(message):
        guard let guildId = message.guild_id?.rawValue else { continue }
        let content = message.content

        if content == "!sounds" {
            let list = soundboard.keys.joined(separator: ", ")
            try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Available sounds: \(list)"))
            continue
        }

        if content == "!stop" {
            if let instance = flightInstances[guildId] {
                instance.player.stop()
                Task { await instance.client.disconnect() }
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Disconnected."))
            }
            continue
        }

        // check if the message is a valid soundboard command
        if let soundUrl = soundboard[content] {
            guard let userChannelId = userVoiceChannels[message.author?.id.rawValue ?? ""] else {
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "You must be in a voice channel first."))
                continue
            }

            // connect to the voice channel
            try? await bot.updateVoiceState(
                payload: .init(guildId: message.guild_id!, channelId: Snowflake(userChannelId), selfMute: false, selfDeaf: false),
            )

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // brief delay to ensure websocket synchronization

                if let instance = flightInstances[guildId] {
                    do {
                        // in a real local-file soundboard this would just be `ffmpegsource(query "sounds/hornmp3")`
                        let source = try FFmpegSource(query: soundUrl)
                        let track = Track(pcmSource: source, metadata: TrackMetadata(title: content))

                        // interrupt immediately no queueing needed for a soundboard
                        instance.player.play(track)
                    } catch {
                        try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Failed to load audio for \(content)."))
                    }
                }
            }
        }

    default:
        break
    }
}
