# Flight Docs

Welcome to Flight! A pure Swift, lightweight, and stupidly simple Discord Voice SDK with DAVE (End-to-End Encryption) support out of the box.

We built Flight because the other voice libraries were way too complicated. We just wanted to stream audio to Discord without fighting with C bindings and weird callback hell.

### What's Inside This Book?

- **[Installation](Book/INSTALLATION.md)**: how to grab the library and toss it in your project
- **[Discord Bot Integration](Book/DISCORD_BOT_INTEGRATION.md)**: how to wire it up to a bot framework like DiscordBM
- **[Usage & Examples](Book/USAGE.md)**: how to connect, play music, stop, and skip songs
- **[Tracks & Metadata](Book/TRACKS_AND_METADATA.md)**: extracting song info, catching player events, and queue state
- **[Audio Sources](Book/AUDIO_SOURCES.md)**: streaming from youtube, local files, and mixing multiple audio streams together
- **[Events & Listening](Book/EVENTS.md)**: detecting when people join/leave, and listening to their incoming voice audio
- **[Connection Lifecycle](Book/CONNECTION_LIFECYCLE.md)**: the voice state machine and auto-reconnecting on drops
- **[Error Handling](Book/ERROR_HANDLING.md)**: catching ffmpeg issues and decoding gateway crashes
- **[Advanced Internals](Book/ADVANCED.md)**: under the hood look at the jitter buffer, continuous clock scheduler, and invisible DAVE E2EE

jump into the installation guide and let's get building!
