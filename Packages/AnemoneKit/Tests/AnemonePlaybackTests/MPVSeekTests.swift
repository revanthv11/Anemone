@testable import AnemonePlayback
import Foundation
import Testing

/// Seeking with the MPV engine: a seek lands when libmpv restarts playback, and one libmpv
/// refuses or never finishes, as on a live stream, doesn't leave the caller waiting. The seek
/// timeouts pass only when a test says, through `ManualTime`.
@MainActor
struct MPVSeekTests {
    @Test func `a seek lands exactly when playback restarts, and a newer seek replaces it`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client, time: ManualTime())
        _ = engine.loadAndStart(on: client)

        let first = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { client.commands.count == 2 })
        let second = Task { await engine.seek(to: .seconds(45)) }
        #expect(await eventually { client.commands.count == 3 })
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        engine.handle(.playbackRestart(entry: 1))

        #expect(await first.value == false)
        #expect(await second.value == true)
        #expect(client.commands.suffix(2) == [
            ["seek", "30.000", "absolute+exact"],
            ["seek", "45.000", "absolute+exact"],
        ])
    }

    @Test func `a seek libmpv refuses doesn't get there, at once`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)
        client.refusedCommands = ["seek"]

        #expect(await engine.seek(to: .seconds(30)) == false)
        #expect(time.running == 0)
    }

    /// libmpv takes the command but never starts the seek, and so never restarts playback, when
    /// it can't seek in the stream, as with a live one.
    @Test func `a seek libmpv never starts doesn't get there once the start timeout passes`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let seek = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { time.running == 1 })
        time.pass()

        #expect(await seek.value == false)
        #expect(time.running == 0)
    }

    @Test func `a seek libmpv started waits past the start timeout for playback to restart`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let seek = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { time.running == 1 })
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        time.pass()
        // Now waiting for it to land.
        #expect(await eventually { time.running == 1 })
        engine.handle(.playbackRestart(entry: 1))

        #expect(await seek.value == true)
    }

    @Test func `a seek that started but never lands gives up once the landing timeout passes`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let seek = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { time.running == 1 })
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        time.pass()
        #expect(await eventually { time.running == 1 })
        time.pass()

        #expect(await seek.value == false)
    }

    @Test func `a seek event from a file a newer load replaced doesn't start the new file's seek`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)
        _ = engine.loadAndStart(on: client, "/next.mkv")

        let seek = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { time.running == 1 })
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        time.pass()

        #expect(await seek.value == false)
    }

    /// libmpv's seek event doesn't say which seek it's for: one for an older seek, sent before
    /// libmpv replied to the newest, is that older one's.
    @Test func `an older seek's event doesn't put the newest seek on the landing timeout`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let older = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { client.asyncIDs.count == 1 })
        engine.reply(on: client)
        let newest = Task { await engine.seek(to: .seconds(45)) }
        #expect(await eventually { client.asyncIDs.count == 2 })
        // The older seek starts and lands before libmpv has replied to the newest.
        engine.handle(.seek(entry: 1))
        engine.handle(.playbackRestart(entry: 1))
        // The newest's start timeout, and the older one's, which the newest replaced.
        #expect(await eventually { time.running == 2 })
        // libmpv never starts the newest, as on a live stream: it gives up on the start timeout.
        engine.reply(on: client)
        time.pass()

        #expect(await newest.value == false)
        #expect(await older.value == false)
        #expect(time.running == 0)
    }

    @Test func `the newest seek starts and lands with the events after libmpv's reply to it`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let older = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { client.asyncIDs.count == 1 })
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        let newest = Task { await engine.seek(to: .seconds(45)) }
        #expect(await eventually { client.asyncIDs.count == 2 })
        // The older one's restart is still on its way.
        engine.handle(.playbackRestart(entry: 1))
        engine.reply(on: client)
        engine.handle(.seek(entry: 1))
        #expect(await eventually { time.running == 2 })
        time.pass()
        #expect(await eventually { time.running == 1 })
        engine.handle(.playbackRestart(entry: 1))

        #expect(await newest.value == true)
        #expect(await older.value == false)
    }

    @Test func `a seek libmpv replies that it refused doesn't get there, at once`() async {
        let client = FakeMPVClient()
        let time = ManualTime()
        let engine = MPVPlayerEngine.testing(client, time: time)
        _ = engine.loadAndStart(on: client)

        let seek = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { client.asyncIDs.count == 1 })
        engine.reply(on: client, succeeded: false)

        #expect(await seek.value == false)
    }

    @Test func `a seek waiting when the engine stops didn't get there`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client, time: ManualTime())
        _ = engine.loadAndStart(on: client)

        async let seek = engine.seek(to: .seconds(30))
        #expect(await eventually { client.commands.count == 2 })
        engine.stop()

        #expect(await seek == false)
        #expect(client.commands.last == ["stop"])
    }

    @Test func `there's no seeking before the file is ready`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client, time: ManualTime())
        _ = engine.load(URL(filePath: "/m.mkv"), from: nil, metadata: PlaybackMetadata(title: "M"))

        #expect(await engine.seek(to: .seconds(30)) == false)
        #expect(client.commands.count == 1)
    }
}
