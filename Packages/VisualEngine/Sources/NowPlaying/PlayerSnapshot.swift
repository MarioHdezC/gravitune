//
//  PlayerSnapshot.swift
//  NowPlaying
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Foundation

public enum MusicPlayer: String, CaseIterable, Sendable {
    case spotify
    case appleMusic

    public var title: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    var changeNotification: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
    }
}

public struct NowPlayingTrack: Equatable, Sendable {
    public let player: MusicPlayer
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let artworkURL: URL?

    public init(player: MusicPlayer, id: String, title: String, artist: String, album: String, artworkURL: URL?) {
        self.player = player
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
    }

    /// Identifies the artwork: tracks from the same album share a key.
    public var artworkKey: String {
        artworkURL?.absoluteString ?? "\(player.rawValue)|\(artist)|\(album)"
    }
}

enum PlaybackState: Equatable, Sendable {
    case playing
    case paused
    case stopped
}

struct PlayerSnapshot: Equatable, Sendable {
    let player: MusicPlayer
    let state: PlaybackState
    let track: NowPlayingTrack?
    var details: PlaybackDetails?

    /// Picks which player to show: the one playing wins and, on a tie, the one already shown.
    static func preferred(among snapshots: [PlayerSnapshot], previous: MusicPlayer?) -> PlayerSnapshot? {
        let candidates = snapshots.filter { $0.track != nil && $0.state != .stopped }
        let playing = candidates.filter { $0.state == .playing }
        let pool = playing.isEmpty ? candidates : playing
        return pool.first { $0.player == previous } ?? pool.first
    }
}
