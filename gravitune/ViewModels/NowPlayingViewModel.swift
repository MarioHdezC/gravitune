//
//  NowPlayingViewModel.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Foundation
import NowPlaying
import Observation
import VisualEngine

/// Current track, its artwork and the player controls.
@Observable
final class NowPlayingViewModel {
    private let provider: any NowPlayingProviding
    private let renderer: FlowRenderer?

    private(set) var cover: Cover?

    init(provider: any NowPlayingProviding = NowPlayingMonitor(), renderer: FlowRenderer?) {
        self.provider = provider
        self.renderer = renderer
    }

    var status: NowPlayingStatus { provider.status }
    var playback: PlaybackDetails? { provider.playback }
    var palette: Palette { cover?.palette ?? .fallback }

    /// Whether a player reports that it's playing. Unlike `isPlaying`, it's not anticipated.
    var isMusicPlaying: Bool {
        if case .active(_, isPlaying: true) = status { return true }
        return false
    }

    var areControlsEnabled: Bool { activePlayer != nil }
    var isPlaying: Bool { playback?.isPlaying ?? false }
    var isShuffling: Bool { playback?.isShuffling ?? false }
    var repeatMode: RepeatMode { playback?.repeatMode ?? .off }
    var volume: Int { playback?.volume ?? 0 }

    private var activePlayer: MusicPlayer? {
        guard case .active(let track, _) = status else { return nil }
        return track.player
    }

    /// Follows the provider and its artwork until the task is cancelled.
    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.provider.run() }
            group.addTask { await self.followArtwork() }
        }
    }

    func subtitle(for track: NowPlayingTrack, isPlaying: Bool) -> String {
        let details = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
        return isPlaying ? details : String(localized: "Paused · \(details)")
    }

    func togglePlayPause() {
        provider.send(.togglePlayPause)
    }

    func skipToNext() {
        provider.send(.next)
    }

    func skipToPrevious() {
        provider.send(.previous)
    }

    func seek(to position: TimeInterval) {
        provider.send(.seek(to: position))
    }

    func setVolume(_ volume: Int) {
        provider.send(.setVolume(volume))
    }

    func toggleShuffle() {
        provider.send(.setShuffle(!isShuffling))
    }

    func cycleRepeatMode() {
        guard let activePlayer else { return }
        provider.send(.setRepeat(repeatMode.next(for: activePlayer)))
    }

    /// Prepares the provider's current artwork.
    func updateCover() async {
        guard let artwork = provider.artwork else {
            setCover(nil)
            return
        }
        setCover(await Cover.extracted(from: artwork.image))
    }

    private func followArtwork() async {
        var currentKey: String?
        for await key in Observations({ self.provider.artwork?.key }) where key != currentKey {
            currentKey = key
            await updateCover()
        }
    }

    private func setCover(_ cover: Cover?) {
        self.cover = cover
        renderer?.setPalette(cover?.palette ?? .fallback)
    }
}
