//
//  NowPlayingMonitorTests.swift
//  NowPlayingTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import NowPlaying

private final class FakeClient: PlayerClient, @unchecked Sendable {
    var results: [MusicPlayer: Result<PlayerSnapshot, PlayerClientError>] = [:]
    var commands: [(PlayerCommand, MusicPlayer)] = []

    func isRunning(_ player: MusicPlayer) -> Bool { results[player] != nil }

    func snapshot(of player: MusicPlayer) async throws -> PlayerSnapshot {
        try results[player, default: .failure(.notRunning)].get()
    }

    func embeddedArtwork(of player: MusicPlayer) async -> Data? { nil }

    func perform(_ command: PlayerCommand, on player: MusicPlayer) async throws {
        commands.append((command, player))
    }
}

private final class CountingLoader: ArtworkLoading, @unchecked Sendable {
    let image: CGImage?
    private(set) var loads = 0

    init(image: CGImage?) {
        self.image = image
    }

    func artwork(for track: NowPlayingTrack, embedded: Data?) async -> CGImage? {
        loads += 1
        return image
    }
}

@MainActor
struct NowPlayingMonitorTests {
    private func track(_ player: MusicPlayer = .spotify, id: String = "1", album: String = "Album") -> NowPlayingTrack {
        NowPlayingTrack(player: player, id: id, title: "Song", artist: "Artist", album: album, artworkURL: nil)
    }

    private func snapshot(_ track: NowPlayingTrack, _ state: PlaybackState = .playing) -> Result<PlayerSnapshot, PlayerClientError> {
        .success(PlayerSnapshot(player: track.player, state: state, track: track))
    }

    private func pixel() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func waitForArtwork(_ monitor: NowPlayingMonitor) async {
        for _ in 0..<200 where monitor.artwork == nil {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func details(isPlaying: Bool = true, position: TimeInterval = 10) -> PlaybackDetails {
        PlaybackDetails(
            isPlaying: isPlaying,
            position: position,
            duration: 100,
            isShuffling: false,
            repeatMode: .off,
            volume: 50,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func commandsGoToTheDisplayedPlayerAndUpdateTheInterfaceAtOnce() async {
        let client = FakeClient()
        let current = track(.appleMusic)
        client.results[.appleMusic] = .success(
            PlayerSnapshot(player: .appleMusic, state: .playing, track: current, details: details())
        )
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))
        await monitor.refresh()

        await monitor.perform(.setShuffle(true))

        #expect(client.commands.first?.0 == .setShuffle(true))
        #expect(client.commands.first?.1 == .appleMusic)
        #expect(monitor.playback?.isShuffling == true)
    }

    @Test func commandsAreIgnoredWithoutATrack() async {
        let client = FakeClient()
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))

        await monitor.perform(.next)

        #expect(client.commands.isEmpty)
    }

    @Test func positionAdvancesOnlyWhilePlaying() {
        let later = Date(timeIntervalSince1970: 5)

        #expect(details().position(at: later) == 15)
        #expect(details(isPlaying: false).position(at: later) == 10)
        #expect(details(position: 98).position(at: later) == 100)
    }

    @Test func seekingMovesTheEstimatedPosition() {
        let now = Date(timeIntervalSince1970: 5)

        #expect(details().applying(.seek(to: 60), at: now).position(at: now) == 60)
    }

    @Test func pausingFreezesThePositionWhereItWas() {
        let now = Date(timeIntervalSince1970: 5)
        let paused = details().applying(.togglePlayPause, at: now)

        #expect(!paused.isPlaying)
        #expect(paused.position(at: Date(timeIntervalSince1970: 50)) == 15)
    }

    @Test func repeatCyclesDependOnThePlayer() {
        #expect(RepeatMode.off.next(for: .spotify) == .all)
        #expect(RepeatMode.all.next(for: .spotify) == .off)
        #expect(RepeatMode.all.next(for: .appleMusic) == .one)
        #expect(RepeatMode.one.next(for: .appleMusic) == .off)
    }

    @Test func reportsNoPlayerWhenNothingIsOpen() async {
        let monitor = NowPlayingMonitor(client: FakeClient(), artworkLoader: CountingLoader(image: nil))

        await monitor.refresh()

        #expect(monitor.status == .noPlayer)
    }

    @Test func reportsIdleWhenThePlayerHasNoTrack() async {
        let client = FakeClient()
        client.results[.spotify] = .success(PlayerSnapshot(player: .spotify, state: .stopped, track: nil))
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))

        await monitor.refresh()

        #expect(monitor.status == .idle)
    }

    @Test func reportsMissingPermission() async {
        let client = FakeClient()
        client.results[.spotify] = .failure(.notAuthorized)
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))

        await monitor.refresh()

        #expect(monitor.status == .notAuthorized(.spotify))
    }

    @Test func aPlayingTrackWinsOverADeniedPlayer() async {
        let client = FakeClient()
        let music = track(.appleMusic)
        client.results[.spotify] = .failure(.notAuthorized)
        client.results[.appleMusic] = snapshot(music)
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))

        await monitor.refresh()

        #expect(monitor.status == .active(music, isPlaying: true))
    }

    @Test func aPlayingPlayerWinsOverAPausedOne() async {
        let client = FakeClient()
        let music = track(.appleMusic)
        client.results[.spotify] = snapshot(track(), .paused)
        client.results[.appleMusic] = snapshot(music)
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))

        await monitor.refresh()

        #expect(monitor.status == .active(music, isPlaying: true))
    }

    @Test func keepsTheCurrentPlayerWhenBothPlay() async {
        let client = FakeClient()
        let music = track(.appleMusic)
        client.results[.appleMusic] = snapshot(music)
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))
        await monitor.refresh()

        client.results[.spotify] = snapshot(track())
        await monitor.refresh()

        #expect(monitor.status == .active(music, isPlaying: true))
    }

    @Test func aTransientFailureKeepsTheCurrentTrack() async {
        let client = FakeClient()
        let current = track()
        client.results[.spotify] = snapshot(current)
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: nil))
        await monitor.refresh()

        client.results[.spotify] = .failure(.failed(code: -1712))
        await monitor.refresh()

        #expect(monitor.status == .active(current, isPlaying: true))
    }

    @Test func tracksOfTheSameAlbumReuseTheArtwork() async throws {
        let client = FakeClient()
        let loader = CountingLoader(image: try pixel())
        client.results[.spotify] = snapshot(track(id: "1"))
        let monitor = NowPlayingMonitor(client: client, artworkLoader: loader)

        await monitor.refresh()
        await waitForArtwork(monitor)
        client.results[.spotify] = snapshot(track(id: "2"))
        await monitor.refresh()
        await Task.yield()

        #expect(monitor.artwork != nil)
        #expect(loader.loads == 1)
    }

    @Test func closingThePlayerClearsTheArtwork() async throws {
        let client = FakeClient()
        client.results[.spotify] = snapshot(track())
        let monitor = NowPlayingMonitor(client: client, artworkLoader: CountingLoader(image: try pixel()))
        await monitor.refresh()
        await waitForArtwork(monitor)

        client.results[.spotify] = nil
        await monitor.refresh()

        #expect(monitor.status == .noPlayer)
        #expect(monitor.artwork == nil)
    }
}
