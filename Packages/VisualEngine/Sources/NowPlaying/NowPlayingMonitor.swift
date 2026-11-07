//
//  NowPlayingMonitor.swift
//  NowPlaying
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Foundation
import Observation
import os

public enum NowPlayingStatus: Equatable, Sendable {
    /// Neither Spotify nor Apple Music is open.
    case noPlayer
    /// A player is open, but nothing is loaded.
    case idle
    /// The user hasn't granted the Automation permission.
    case notAuthorized(MusicPlayer)
    case active(NowPlayingTrack, isPlaying: Bool)
}

extension NowPlayingStatus {
    /// Description with no track data, safe for logs.
    fileprivate var logDescription: String {
        switch self {
        case .noPlayer: "no player"
        case .idle: "no track"
        case .notAuthorized(let player): "no permission for \(player.rawValue)"
        case .active(let track, let isPlaying): "\(track.player.rawValue), \(isPlaying ? "playing" : "paused")"
        }
    }
}

public struct TrackArtwork: Sendable {
    public let key: String
    public let image: CGImage

    public init(key: String, image: CGImage) {
        self.key = key
        self.image = image
    }
}

/// What the app needs from a source of playback information.
@MainActor
public protocol NowPlayingProviding: AnyObject, Observable, Sendable {
    var status: NowPlayingStatus { get }
    var artwork: TrackArtwork? { get }
    var playback: PlaybackDetails? { get }

    /// Follows the players until the task is cancelled.
    func run() async

    /// Sends a command to the player being shown.
    func send(_ command: PlayerCommand)
}

@MainActor
@Observable
public final class NowPlayingMonitor: NowPlayingProviding {
    private static let pollInterval: Duration = .seconds(3)
    private nonisolated static let logger = Logger(subsystem: "com.mariohernandez.gravitune", category: "NowPlaying")

    public private(set) var status = NowPlayingStatus.noPlayer
    public private(set) var artwork: TrackArtwork?
    public private(set) var playback: PlaybackDetails?

    private let client: PlayerClient
    private let artworkLoader: ArtworkLoading
    private var currentArtworkKey: String?
    private var artworkTask: Task<Void, Never>?
    private var wakeUp: AsyncStream<Void>.Continuation?

    public convenience init() {
        self.init(client: AppleScriptPlayerClient(), artworkLoader: ArtworkLoader())
    }

    init(client: PlayerClient, artworkLoader: ArtworkLoading) {
        self.client = client
        self.artworkLoader = artworkLoader
    }

    /// Follows the players until the task is cancelled.
    ///
    /// Notifications give the immediate response; polling covers what they don't report,
    /// such as opening or closing a player.
    public func run() async {
        let (wakeUps, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        wakeUp = continuation

        let center = DistributedNotificationCenter.default()
        let observers = MusicPlayer.allCases.map { player in
            center.addObserver(forName: player.changeNotification, object: nil, queue: nil) { _ in
                Self.logger.debug("Notification from \(player.rawValue, privacy: .public)")
                continuation.yield()
            }
        }
        let poller = Task {
            while !Task.isCancelled {
                continuation.yield()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        defer {
            poller.cancel()
            observers.forEach(center.removeObserver)
            artworkTask?.cancel()
        }

        await withTaskCancellationHandler {
            for await _ in wakeUps {
                await refresh()
            }
        } onCancel: {
            continuation.finish()
        }
    }

    /// Sends a command to the player being shown.
    public func send(_ command: PlayerCommand) {
        Task { await perform(command) }
    }

    func perform(_ command: PlayerCommand) async {
        guard case .active(let track, _) = status else { return }
        playback = playback?.applying(command, at: .now)
        do {
            try await client.perform(command, on: track.player)
        } catch {
            Self.logger.error("Command failed in \(track.player.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        wakeUp?.yield()
    }

    func refresh() async {
        var snapshots: [PlayerSnapshot] = []
        var deniedPlayer: MusicPlayer?
        var hasRunningPlayer = false
        var hadTransientFailure = false

        for player in MusicPlayer.allCases where client.isRunning(player) {
            hasRunningPlayer = true
            do {
                snapshots.append(try await client.snapshot(of: player))
            } catch PlayerClientError.notAuthorized {
                Self.logger.error("No permission for \(player.rawValue, privacy: .public)")
                deniedPlayer = deniedPlayer ?? player
            } catch PlayerClientError.notRunning {
                continue
            } catch {
                Self.logger.error("Failure in \(player.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                hadTransientFailure = true
            }
        }

        let previous: MusicPlayer?
        if case .active(let track, _) = status { previous = track.player } else { previous = nil }

        if let preferred = PlayerSnapshot.preferred(among: snapshots, previous: previous),
           let track = preferred.track {
            update(.active(track, isPlaying: preferred.state == .playing))
            playback = preferred.details
            if let details = preferred.details {
                Self.logger.debug("Position \(details.position, privacy: .public) of \(details.duration, privacy: .public) s, volume \(details.volume, privacy: .public)")
            }
            loadArtworkIfNeeded(for: track)
        } else if let deniedPlayer {
            update(.notAuthorized(deniedPlayer))
            clearArtwork()
        } else if !hadTransientFailure {
            // After a one-off failure, what's on screen is kept to avoid flickering.
            update(hasRunningPlayer ? .idle : .noPlayer)
            clearArtwork()
        }
    }

    private func update(_ newStatus: NowPlayingStatus) {
        guard status != newStatus else { return }
        Self.logger.info("Status: \(newStatus.logDescription, privacy: .public)")
        status = newStatus
    }

    private func clearArtwork() {
        artworkTask?.cancel()
        playback = nil
        currentArtworkKey = nil
        artwork = nil
    }

    private func loadArtworkIfNeeded(for track: NowPlayingTrack) {
        guard track.artworkKey != currentArtworkKey else { return }
        currentArtworkKey = track.artworkKey
        artworkTask?.cancel()
        artworkTask = Task {
            let embedded = await client.embeddedArtwork(of: track.player)
            let image = await artworkLoader.artwork(for: track, embedded: embedded)
            guard !Task.isCancelled else { return }
            Self.logger.info("Artwork from \(track.player.rawValue, privacy: .public): \(image == nil ? "not found" : "loaded", privacy: .public)")
            artwork = image.map { TrackArtwork(key: track.artworkKey, image: $0) }
        }
    }
}
