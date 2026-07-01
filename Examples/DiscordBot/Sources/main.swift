import AsyncHTTPClient
import DiscordBM
import Flight
import Foundation
import NIO
import NIOConcurrencyHelpers

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
        activities: [.init(name: "Music via Flight", type: .listening)],
        status: .online,
        afk: false,
    ),
    intents: [.guilds, .guildMessages, .messageContent, .guildVoiceStates],
)

// global state variables
var myBotId = ""
var userVoiceChannels: [String: String] = [:]

/// this structure groups the required flight components for each server (guild)
struct FlightInstance {
    let client: VoiceClient
    let player: AudioPlayer
    let queue: QueueManager
}

var flightInstances: [String: FlightInstance] = [:]
var tempSessionIds: [String: String] = [:]

/// a thread-safe boolean to control the volume logger feature
let isEchoEnabled = NIOLockedValueBox(false)

// start the bot connection
Task {
    await bot.connect()
}

// the main event loop that processes all incoming discord events
// this loop will run indefinitely and keep the main thread alive
for await event in await bot.events {
    switch event.data {
    case let .ready(ready):
        myBotId = ready.user.id.rawValue
        print("Bot connected successfully as \(ready.user.username).")

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
                let queue = QueueManager()

                flightInstances[guildId] = FlightInstance(client: client, player: player, queue: queue)

                // voice receiver setup logs user volume levels when they speak
                client.onAudioReceived = { userId, pcm in
                    guard isEchoEnabled.withLockedValue({ $0 }) else { return }

                    // calculate rms (root mean square) volume in decibels
                    var sumSquares: Float = 0
                    for sample in pcm {
                        let floatSample = Float(sample) / 32768.0
                        sumSquares += floatSample * floatSample
                    }
                    let rms = sqrt(sumSquares / Float(pcm.count))
                    let db = 20 * log10(rms)

                    // filter out background noise by only logging values above -35 db
                    if db > -35 {
                        print("User \(userId) is speaking (Volume: \(String(format: "%.2f", db)) dB)")
                    }
                }

                client.onUserConnect = { userIds in
                    print("Users connected to voice: \(userIds)")
                }

                client.onUserDisconnect = { userId in
                    print("User disconnected from voice: \(userId)")
                }

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

        if content.starts(with: "!play ") {
            let url = String(content.dropFirst("!play ".count)).trimmingCharacters(in: .whitespaces)

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
                        let source = try FFmpegSource(query: url)
                        let track = Track(pcmSource: source, metadata: TrackMetadata(title: url))

                        instance.queue.enqueue(track)
                        if instance.player.state == .stopped {
                            instance.player.play(queue: instance.queue)
                            try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Now playing: \(url)"))
                        } else {
                            try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Added to queue."))
                        }
                    } catch {
                        try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Failed to load audio."))
                    }
                }
            }
        } else if content == "!skip" {
            if let instance = flightInstances[guildId] {
                _ = instance.queue.skip()
                instance.player.play(queue: instance.queue)
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Track skipped."))
            }
        } else if content == "!pause" {
            if let instance = flightInstances[guildId] {
                instance.player.pause()
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Playback paused."))
            }
        } else if content == "!resume" {
            if let instance = flightInstances[guildId] {
                instance.player.resume()
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Playback resumed."))
            }
        } else if content == "!queue" {
            if let instance = flightInstances[guildId] {
                let tracks = instance.queue.tracks
                let text = tracks.enumerated().map { "\($0.offset + 1). \($0.element.metadata.title)" }.joined(separator: "\n")
                let reply = text.isEmpty ? "The queue is currently empty." : "Queue:\n\(text)"
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: reply))
            }
        } else if content == "!clear" {
            if let instance = flightInstances[guildId] {
                instance.queue.clear()
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Queue cleared."))
            }
        } else if content.starts(with: "!volume ") {
            if let instance = flightInstances[guildId] {
                let str = String(content.dropFirst("!volume ".count)).trimmingCharacters(in: .whitespaces)
                if let vol = Float(str) {
                    instance.player.setVolume(vol)
                    try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Volume set to \(vol)."))
                }
            }
        } else if content == "!stop" {
            if let instance = flightInstances[guildId] {
                instance.player.stop()
                instance.queue.clear()
                Task { await instance.client.disconnect() }
                try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Playback stopped and disconnected."))
            }
        } else if content == "!echo on" {
            isEchoEnabled.withLockedValue { $0 = true }
            try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Voice logger enabled. Check the terminal output when you speak."))
        } else if content == "!echo off" {
            isEchoEnabled.withLockedValue { $0 = false }
            try? await bot.client.createMessage(channelId: message.channel_id, payload: .init(content: "Voice logger disabled."))
        }

    default:
        break
    }
}
