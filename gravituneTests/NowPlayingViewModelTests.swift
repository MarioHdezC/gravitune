//
//  NowPlayingViewModelTests.swift
//  gravituneTests
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import NowPlaying
import Testing
import VisualEngine
@testable import gravitune

struct NowPlayingViewModelTests {
    private let provider = FakeNowPlayingProvider()
    private let viewModel: NowPlayingViewModel

    init() {
        viewModel = NowPlayingViewModel(provider: provider, renderer: nil)
    }

    @Test func controlsAreDisabledWithoutAnActiveTrack() {
        provider.status = .idle
        #expect(!viewModel.areControlsEnabled)

        provider.status = .active(.sample(), isPlaying: false)
        #expect(viewModel.areControlsEnabled)
    }

    @Test func onlyAPlayingTrackCountsAsMusicPlaying() {
        provider.status = .active(.sample(), isPlaying: false)
        #expect(!viewModel.isMusicPlaying)

        provider.status = .active(.sample(), isPlaying: true)
        #expect(viewModel.isMusicPlaying)
    }

    @Test func playbackDefaultsWithoutDetails() {
        #expect(!viewModel.isPlaying)
        #expect(!viewModel.isShuffling)
        #expect(viewModel.repeatMode == .off)
        #expect(viewModel.volume == 0)
    }

    @Test func simpleControlsSendTheirCommands() {
        viewModel.togglePlayPause()
        viewModel.skipToNext()
        viewModel.skipToPrevious()
        viewModel.seek(to: 42)
        viewModel.setVolume(30)

        #expect(provider.sentCommands == [
            .togglePlayPause, .next, .previous, .seek(to: 42), .setVolume(30)
        ])
    }

    @Test(arguments: [false, true])
    func shuffleTogglesTheCurrentValue(isShuffling: Bool) {
        provider.playback = .sample(isShuffling: isShuffling)

        viewModel.toggleShuffle()

        #expect(provider.sentCommands == [.setShuffle(!isShuffling)])
    }

    @Test func repeatCyclesAccordingToThePlayer() {
        provider.status = .active(.sample(player: .appleMusic), isPlaying: true)
        provider.playback = .sample(repeatMode: .all)
        viewModel.cycleRepeatMode()
        #expect(provider.sentCommands == [.setRepeat(.one)])
    }

    @Test func repeatIsIgnoredWithoutAnActivePlayer() {
        viewModel.cycleRepeatMode()
        #expect(provider.sentCommands.isEmpty)
    }

    @Test func subtitleSkipsMissingDetails() {
        let track = NowPlayingTrack.sample(artist: "", album: "Album")
        #expect(viewModel.subtitle(for: track, isPlaying: true) == "Album")
    }

    @Test func subtitleJoinsArtistAndAlbum() {
        #expect(viewModel.subtitle(for: .sample(), isPlaying: true) == "Artist · Album")
    }

    @Test func subtitleMentionsThePause() {
        #expect(viewModel.subtitle(for: .sample(), isPlaying: false).hasSuffix("Artist · Album"))
        #expect(viewModel.subtitle(for: .sample(), isPlaying: false) != "Artist · Album")
    }

    @Test func paletteComesFromTheCoverAndFallsBackWithoutIt() async throws {
        #expect(viewModel.palette == .fallback)

        provider.artwork = TrackArtwork(key: "a", image: try makeImage())
        await viewModel.updateCover()
        #expect(viewModel.cover != nil)
        #expect(viewModel.palette != .fallback)

        provider.artwork = nil
        await viewModel.updateCover()
        #expect(viewModel.cover == nil)
        #expect(viewModel.palette == .fallback)
    }

    @Test func runFollowsTheArtworkAndKeepsTheCoverWhileTheKeyIsTheSame() async throws {
        let task = Task { await viewModel.run() }
        defer { task.cancel() }

        let image = try makeImage()
        provider.artwork = TrackArtwork(key: "a", image: image)
        try await waitUntil { viewModel.cover != nil }
        let firstCover = viewModel.cover?.id

        provider.artwork = TrackArtwork(key: "a", image: image)
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.cover?.id == firstCover)

        provider.artwork = nil
        try await waitUntil { viewModel.cover == nil }
    }
}
