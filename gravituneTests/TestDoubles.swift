//
//  TestDoubles.swift
//  gravituneTests
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import AppKit
import CoreGraphics
import NowPlaying
import Observation
import Testing
@testable import Gravitune

@Observable
final class FakeNowPlayingProvider: NowPlayingProviding {
    var status = NowPlayingStatus.noPlayer
    var artwork: TrackArtwork?
    var playback: PlaybackDetails?
    private(set) var sentCommands: [PlayerCommand] = []

    func run() async {}

    func send(_ command: PlayerCommand) {
        sentCommands.append(command)
    }
}

@Observable
final class FakeDisplayRouter: DisplayRouting {
    var availableDisplays: [ExternalDisplay] = []
    var isMirroring = false
    var selectedDisplayID: CGDirectDisplayID?

    func run(makeStageView: @escaping @MainActor () -> NSView) async {}
}

extension NowPlayingTrack {
    static func sample(
        player: MusicPlayer = .spotify,
        artist: String = "Artist",
        album: String = "Album"
    ) -> NowPlayingTrack {
        NowPlayingTrack(player: player, id: "1", title: "Song", artist: artist, album: album, artworkURL: nil)
    }
}

extension PlaybackDetails {
    static func sample(
        isPlaying: Bool = true,
        isShuffling: Bool = false,
        repeatMode: RepeatMode = .off
    ) -> PlaybackDetails {
        PlaybackDetails(
            isPlaying: isPlaying,
            position: 0,
            duration: 200,
            isShuffling: isShuffling,
            repeatMode: repeatMode,
            volume: 50
        )
    }
}

/// Creates a solid red image.
func makeImage() throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return try #require(context.makeImage())
}

/// Waits for a condition that depends on background work.
func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
